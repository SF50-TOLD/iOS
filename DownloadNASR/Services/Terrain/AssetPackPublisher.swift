import Foundation
import Logging
import SF50_Shared

/// Errors that can occur while packaging terrain payloads as asset packs.
enum AssetPackPublisherError: LocalizedError {
  case packagingFailed(command: String, exitCode: Int32, output: String)
  case payloadMissing(region: TerrainRegion)

  var errorDescription: String? {
    String(localized: "Asset-pack packaging failed.")
  }

  var failureReason: String? {
    switch self {
      case .packagingFailed(let command, let exitCode, let output):
        String(localized: "“\(command)” exited with status \(exitCode, format: .number): \(output)")
      case .payloadMissing(let region):
        String(
          localized:
            "No payload for \(region.displayName) in the output directory. Process the region, or copy its .srtm file there, before packaging."
        )
    }
  }
}

/// Packages published terrain payloads as self-hosted Background Assets asset packs.
///
/// Each region becomes one asset pack whose ID is that region's download identifier, so a pack
/// and the Background Assets download it supersedes are named alike. Both the packs and the
/// download manifest that indexes them are produced by Xcode's `ba-package` tool, which is the
/// only supported writer of either format.
///
/// The download manifest this writes is what the app's `BAManifestURL` points at. It is a
/// different document from the terrain manifest bundled in the app, which carries the payload
/// sizes the settings screen displays.
actor AssetPackPublisher {

  // MARK: - Type Properties

  /// Name the Background Assets download manifest is written and published under.
  static let downloadManifestFilename = "terrain-asset-packs-ios.json"

  /// Key prefix the packs are published under, and the last path component of their base URL.
  ///
  /// `ba-package` builds each pack's download URL by appending its ID to the base URL, so a
  /// pack's object key is this prefix followed by the pack ID and no extension.
  static let packKeyPrefix = "terrain-packs"

  /// Extension `ba-package` gives an asset-pack archive.
  private static let archiveExtension = "aar"

  /// Installation events the system considers a terrain pack for.
  ///
  /// The packs are published as `prefetch` rather than `onDemand` so the system offers every
  /// region at install time and the downloader extension narrows them to the one matching the
  /// device's locale, which is what the app did before it adopted managed packs.
  private static let installationEventTypes = ["firstInstallation", "subsequentUpdate"]

  // MARK: - Instance Properties

  /// Directory holding the `.srtm` payloads, and where archives are written.
  let outputLocation: URL

  /// Logger for status messages and errors.
  let logger: Logger

  // MARK: - Initializers

  init(outputLocation: URL, logger: Logger) {
    self.outputLocation = outputLocation
    self.logger = logger
  }

  // MARK: - Type Methods

  /// Runs a tool under `xcrun` and returns everything it wrote.
  ///
  /// Synchronous by design: callers hand this to a detached task rather than blocking a
  /// cooperative thread, and keeping `Process` inside one non-isolated call avoids sending a
  /// non-`Sendable` value across an isolation boundary.
  nonisolated private static func runXcrun(
    _ arguments: [String],
    workingDirectory: URL
  ) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    process.arguments = arguments
    process.currentDirectoryURL = workingDirectory

    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe

    try process.run()
    // Read to EOF before waiting, so a tool that outfills the pipe buffer cannot deadlock.
    let outputData = try pipe.fileHandleForReading.readToEnd() ?? Data()
    let output = String(bytes: outputData, encoding: .utf8) ?? ""
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
      throw AssetPackPublisherError.packagingFailed(
        command: (["xcrun"] + arguments).joined(separator: " "),
        exitCode: process.terminationStatus,
        output: output.trimmingCharacters(in: .whitespacesAndNewlines)
      )
    }
    return output
  }

  // MARK: - Methods

  /// Packages one region's payload into an asset-pack archive, and returns where it landed.
  ///
  /// An archive that already postdates its payload is left alone. Compressing a multi-gigabyte
  /// region is expensive, and a run that reprocesses one region should not repackage the ten it
  /// did not touch.
  func packageRegion(_ region: TerrainRegion) async throws -> PackagedRegion {
    try verifyPayloadExists(for: region)

    let archiveURL = archiveURL(for: region)
    if archiveIsCurrent(archiveURL, for: region) {
      logger.info("Reusing existing asset pack for \(region.downloadIdentifier)")
      return .init(region: region, archiveURL: archiveURL, isRebuilt: false)
    }

    let manifestURL = try writePackManifest(for: region)
    defer { try? FileManager.default.removeItem(at: manifestURL) }

    try? FileManager.default.removeItem(at: archiveURL)

    let arguments = ["ba-package", manifestURL.path, "-o", archiveURL.path]
    let output = try await runPackagingTool(arguments)
    logger.info("Packaged \(region.downloadIdentifier): \(output)")

    return .init(region: region, archiveURL: archiveURL, isRebuilt: true)
  }

  /// Writes the download manifest indexing every packaged region, and returns where it landed.
  ///
  /// A device re-downloads a pack when its version rises, so only rebuilt packs may have their
  /// versions bumped: `ba-package download-manifest update` increments exactly the packs it is
  /// handed, leaving the rest of the manifest alone. Falling back to `create` would reset every
  /// pack to version 0 and strand devices on whatever they already hold, so `create` is used
  /// only when there is no prior manifest to carry versions forward from.
  ///
  /// - Parameters:
  ///   - packaged: Every region's archive, rebuilt or reused.
  ///   - downloadBaseURL: Base URL the packs are served from; `ba-package` appends each pack's
  ///     ID to it to form that pack's download URL.
  func writeDownloadManifest(
    for packaged: [PackagedRegion],
    downloadBaseURL: String
  ) async throws -> URL {
    let manifestURL = outputLocation.appendingPathComponent(Self.downloadManifestFilename)
    await adoptPublishedManifest(at: manifestURL, downloadBaseURL: downloadBaseURL)

    let platformAndBase = ["--ios", "--download-base-url", downloadBaseURL]
    let rebuilt = packaged.filter(\.isRebuilt)

    guard FileManager.default.fileExists(atPath: manifestURL.path) else {
      let arguments =
        ["ba-package", "download-manifest", "create"] + packaged.map(\.archiveURL.path)
        + platformAndBase + ["-o", manifestURL.path]
      let output = try await runPackagingTool(arguments)
      logger.notice("Created \(Self.downloadManifestFilename) at version 0: \(output)")
      return manifestURL
    }

    guard !rebuilt.isEmpty else {
      logger.notice("No asset pack changed; leaving \(Self.downloadManifestFilename) as published")
      return manifestURL
    }

    let arguments =
      ["ba-package", "download-manifest", "update", manifestURL.path, "--asset-pack-paths"]
      + rebuilt.map(\.archiveURL.path) + platformAndBase
    let output = try await runPackagingTool(arguments)
    logger.notice(
      "Bumped \(rebuilt.count) asset pack version(s) in \(Self.downloadManifestFilename): \(output)"
    )

    return manifestURL
  }

  /// Fetches the currently published download manifest when this machine has no local copy.
  ///
  /// Without it, a run from a fresh checkout would have nothing to update and would `create` a
  /// manifest that resets every pack to version 0.
  private func adoptPublishedManifest(at manifestURL: URL, downloadBaseURL: String) async {
    guard !FileManager.default.fileExists(atPath: manifestURL.path) else { return }
    guard
      let publishedURL = URL(string: downloadBaseURL)?
        .deletingLastPathComponent()
        .appendingPathComponent(Self.downloadManifestFilename)
    else { return }

    do {
      let (data, response) = try await URLSession.shared.data(from: publishedURL)
      guard (response as? HTTPURLResponse)?.statusCode == 200 else {
        logger.notice("No published download manifest at \(publishedURL); starting fresh")
        return
      }
      try data.write(to: manifestURL)
      logger.notice("Adopted the published download manifest to carry pack versions forward")
    } catch {
      logger.warning(
        "Couldn’t read the published download manifest (\(error.localizedDescription)); starting fresh"
      )
    }
  }

  /// Object key the given region's archive is published under.
  nonisolated func publishedKey(for region: TerrainRegion) -> String {
    "\(Self.packKeyPrefix)/\(region.downloadIdentifier)"
  }

  /// Where the given region's archive is written.
  nonisolated func archiveURL(for region: TerrainRegion) -> URL {
    outputLocation
      .appendingPathComponent(region.downloadIdentifier)
      .appendingPathExtension(Self.archiveExtension)
  }

  /// Whether an archive already exists and is no older than the payload it was built from.
  private func archiveIsCurrent(_ archiveURL: URL, for region: TerrainRegion) -> Bool {
    let payloadURL = outputLocation.appendingPathComponent(region.remoteFilename)
    guard let archiveDate = modificationDate(of: archiveURL),
      let payloadDate = modificationDate(of: payloadURL)
    else { return false }
    return archiveDate >= payloadDate
  }

  private func modificationDate(of url: URL) -> Date? {
    try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
  }

  private func verifyPayloadExists(for region: TerrainRegion) throws {
    let payloadURL = outputLocation.appendingPathComponent(region.remoteFilename)
    guard FileManager.default.fileExists(atPath: payloadURL.path) else {
      throw AssetPackPublisherError.payloadMissing(region: region)
    }
  }

  /// Writes the asset-pack manifest describing one region, for `ba-package` to consume.
  ///
  /// The file selector is a bare filename because `ba-package` resolves selector paths against
  /// its working directory, which is the payload directory.
  private func writePackManifest(for region: TerrainRegion) throws -> URL {
    let manifest = PackManifest(
      assetPackID: region.downloadIdentifier,
      downloadPolicy: .init(prefetch: .init(installationEventTypes: Self.installationEventTypes)),
      fileSelectors: [.init(file: region.remoteFilename)],
      platforms: ["iOS"],
      userInfo: ["regionID": region.rawValue]
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

    let manifestURL =
      outputLocation
      .appendingPathComponent("Manifest-\(region.downloadIdentifier)")
      .appendingPathExtension("json")
    try encoder.encode(manifest).write(to: manifestURL)

    return manifestURL
  }

  private func runPackagingTool(_ arguments: [String]) async throws -> String {
    let outputLocation = outputLocation
    return try await Task.detached(priority: .userInitiated) {
      try Self.runXcrun(arguments, workingDirectory: outputLocation)
    }.value
  }

  // MARK: - Nested Types

  /// One region's asset pack as this run left it.
  struct PackagedRegion: Sendable {
    let region: TerrainRegion
    let archiveURL: URL
    /// Whether this run rebuilt the archive, as opposed to reusing a current one.
    let isRebuilt: Bool
  }

  /// The asset-pack manifest schema `ba-package` reads.
  ///
  /// Mirrors the template `xcrun ba-package template` emits. `userInfo` is supported only for
  /// self-hosted packs, which is what these are.
  private struct PackManifest: Encodable {
    let assetPackID: String
    let downloadPolicy: DownloadPolicy
    let fileSelectors: [FileSelector]
    let platforms: [String]
    let userInfo: [String: String]

    struct DownloadPolicy: Encodable {
      let prefetch: Prefetch

      struct Prefetch: Encodable {
        let installationEventTypes: [String]
      }
    }

    struct FileSelector: Encodable {
      let file: String
    }
  }
}
