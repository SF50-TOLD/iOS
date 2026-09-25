import Foundation
import Logging
import SF50_Shared

/// Errors that can occur while packaging terrain payloads as asset packs.
enum AssetPackPublisherError: LocalizedError {
  case packagingFailed(command: String, exitCode: Int32, output: String)
  case payloadMissing(region: TerrainRegion)
  case packMissingFromManifest(region: TerrainRegion)

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
      case .packMissingFromManifest(let region):
        String(
          localized:
            "The download manifest has no pack for \(region.displayName) under the public URL."
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
/// Each pack carries its payload's SHA-256 in a file beside the payload: Background Assets
/// verifies nothing about a pack's contents, so the app checks the digest itself. A published archive is never replaced. A rebuilt pack is published under a key
/// stamped with the run that built it, and its version rises, which is what makes installed
/// copies update, while devices part-way through the previous version finish against unchanged
/// bytes.
///
/// The download manifest this writes is what the app's `BAManifestURL` points at. It is a
/// different document from the terrain manifest bundled in the app, which carries the payload
/// sizes the settings screen displays.
actor AssetPackPublisher {

  // MARK: - Type Properties

  /// Name the Background Assets download manifest is written and published under.
  static let downloadManifestFilename = "terrain-asset-packs-ios.json"

  /// Key prefix the packs are published under.
  ///
  /// `ba-package` builds each pack's download URL by appending its ID to the base URL, so a
  /// rebuilt pack's object key is this prefix, the run's release stamp, then the pack ID, with no
  /// extension.
  static let packKeyPrefix = "terrain-packs"

  /// Extension `ba-package` gives an asset-pack archive.
  private static let archiveExtension = "aar"

  /// The developer directory of Xcode's default install location.
  private static let defaultDeveloperDirectory = "/Applications/Xcode.app/Contents/Developer"

  /// Key in each pack's `userInfo` holding its payload's SHA-256, which `ba-package` copies into
  /// the download manifest. It is what says which packs a manifest already describes.
  private static let payloadDigestKey = "payloadSHA256"

  /// Installation events the system considers a terrain pack for.
  ///
  /// The packs are published as `prefetch` rather than `onDemand` so the system offers every
  /// region at install time and the downloader extension narrows them to the one matching the
  /// device's locale, which is what the app did before it adopted managed packs.
  private static let installationEventTypes = ["firstInstallation", "subsequentUpdate"]

  /// Where the active Xcode keeps `ba-package`.
  ///
  /// `xcrun` refuses to run inside an App Sandbox, which this app is, so the tool is run directly
  /// from the developer directory: `DEVELOPER_DIR` when it is set, as `xcrun` would honour, and the
  /// default Xcode otherwise.
  nonisolated private static var packagingToolURL: URL {
    let developerDirectory =
      ProcessInfo.processInfo.environment["DEVELOPER_DIR"] ?? defaultDeveloperDirectory
    return URL(filePath: developerDirectory).appending(path: "usr/bin/ba-package")
  }

  // MARK: - Instance Properties

  /// Directory holding the `.srtm` payloads, and where archives are written.
  let outputLocation: URL

  /// Logger for status messages and errors.
  let logger: Logger

  /// Base URL this run's rebuilt packs are served from; `ba-package` appends each pack's ID.
  let downloadBaseURL: String

  // MARK: - Initializers

  /// - Parameters:
  ///   - outputLocation: Directory holding the payloads, where archives are written.
  ///   - logger: Logger for status messages and errors.
  ///   - publicRoot: Public URL of the bucket the packs are published to.
  ///   - releaseStamp: Names this run's rebuilt packs apart from every earlier run's.
  init(outputLocation: URL, logger: Logger, publicRoot: String, releaseStamp: String) {
    self.outputLocation = outputLocation
    self.logger = logger
    let trimmedRoot = publicRoot.hasSuffix("/") ? String(publicRoot.dropLast()) : publicRoot
    self.downloadBaseURL = "\(trimmedRoot)/\(Self.packKeyPrefix)/\(releaseStamp)"
  }

  // MARK: - Type Methods

  /// Runs `ba-package` and returns everything it wrote.
  ///
  /// Synchronous by design: callers hand this to a detached task rather than blocking a
  /// cooperative thread, and keeping `Process` inside one non-isolated call avoids sending a
  /// non-`Sendable` value across an isolation boundary.
  nonisolated private static func runBAPackage(
    _ arguments: [String],
    workingDirectory: URL
  ) throws -> String {
    let process = Process()
    process.executableURL = packagingToolURL
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
        command: ([packagingToolURL.path] + arguments).joined(separator: " "),
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
    let digest = try payloadDigest(for: region)

    let archiveURL = archiveURL(for: region)
    if archiveIsCurrent(archiveURL, for: region) {
      logger.info("Reusing existing asset pack for \(region.downloadIdentifier)")
      return .init(region: region, archiveURL: archiveURL, payloadDigest: digest, isRebuilt: false)
    }

    let manifestURL = try writePackManifest(for: region, payloadDigest: digest)
    defer { try? FileManager.default.removeItem(at: manifestURL) }

    try? FileManager.default.removeItem(at: archiveURL)

    let arguments = [manifestURL.path, "-o", archiveURL.path]
    let output = try await runPackagingTool(arguments)
    logger.info("Packaged \(region.downloadIdentifier): \(output)")

    return .init(region: region, archiveURL: archiveURL, payloadDigest: digest, isRebuilt: true)
  }

  /// Writes the download manifest indexing every packaged region, and returns where it landed.
  ///
  /// A device re-downloads a pack when its version rises, so only packs whose payload changed may
  /// have their versions bumped: `ba-package download-manifest update` increments exactly the
  /// packs it is handed, pointing each at ``downloadBaseURL``, and leaves the rest of the manifest
  /// alone. A pack has changed when its manifest entry doesn't carry its payload's digest, which
  /// holds however many runs it took to get here, a failed one included. Falling back to `create`
  /// would reset every pack to version 0 and strand devices on whatever they already hold, so
  /// `create` is used only when there is no prior manifest to carry versions forward from.
  ///
  /// - Parameter packaged: Every region's archive, rebuilt or reused.
  func writeDownloadManifest(for packaged: [PackagedRegion]) async throws -> URL {
    let manifestURL = outputLocation.appendingPathComponent(Self.downloadManifestFilename)
    await adoptPublishedManifest(at: manifestURL)

    let platformAndBase = ["--ios", "--download-base-url", downloadBaseURL]

    guard FileManager.default.fileExists(atPath: manifestURL.path) else {
      let arguments =
        ["download-manifest", "create"] + packaged.map(\.archiveURL.path)
        + platformAndBase + ["-o", manifestURL.path]
      let output = try await runPackagingTool(arguments)
      logger.notice("Created \(Self.downloadManifestFilename) at version 0: \(output)")
      return manifestURL
    }

    let changed = try packs(in: packaged, changedSinceManifestAt: manifestURL)
    guard !changed.isEmpty else {
      logger.notice("No asset pack changed; leaving \(Self.downloadManifestFilename) as it stands")
      return manifestURL
    }

    let archiveAliases = try aliasArchivesForUpdate(changed)
    defer { try? FileManager.default.removeItem(at: archiveAliases.directory) }

    // Each path takes a flag of its own; the tool reads only the first after a single flag.
    let arguments =
      ["download-manifest", "update", manifestURL.path]
      + archiveAliases.paths.flatMap { ["--asset-pack-paths", $0] } + platformAndBase
    let output = try await runPackagingTool(arguments)
    logger.notice(
      "Bumped \(changed.count) asset pack version(s) in \(Self.downloadManifestFilename): \(output)"
    )

    return manifestURL
  }

  /// The packs whose entry in the download manifest at `manifestURL` doesn't carry the digest of
  /// the payload they hold now.
  private func packs(
    in packaged: [PackagedRegion],
    changedSinceManifestAt manifestURL: URL
  ) throws -> [PackagedRegion] {
    let manifest = try JSONDecoder().decode(
      DownloadManifest.self,
      from: Data(contentsOf: manifestURL)
    )
    let publishedDigests = Dictionary(
      manifest.assetPacks.map { ($0.id, $0.userInfo?[Self.payloadDigestKey]) },
      uniquingKeysWith: { first, _ in first }
    )
    return packaged.filter { publishedDigests[$0.region.downloadIdentifier] != $0.payloadDigest }
  }

  /// Links each archive under a `.json` name, the only extension `download-manifest update`
  /// accepts for an asset-pack path, although it reads the archive behind it.
  ///
  /// The links are hard links: the tool takes a pack's download size from the path it is given,
  /// and a symbolic link would report its own few bytes. `download-manifest create` takes the
  /// `.aar` paths as they are.
  private func aliasArchivesForUpdate(
    _ packs: [PackagedRegion]
  ) throws -> (directory: URL, paths: [String]) {
    let directory = outputLocation.appendingPathComponent(".archive-aliases-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let paths = try packs.map { pack in
      let alias = directory.appendingPathComponent(pack.region.downloadIdentifier)
        .appendingPathExtension("json")
      try FileManager.default.linkItem(at: pack.archiveURL, to: alias)
      return alias.path
    }
    return (directory, paths)
  }

  /// Where each pack in the download manifest at `manifestURL` is served from, as object keys
  /// under `publicRoot`.
  ///
  /// The manifest is the one record of which archive each pack's URL names, so uploads follow it
  /// rather than recomputing keys.
  nonisolated func publishedKeys(
    inManifestAt manifestURL: URL,
    publicRoot: String
  ) throws -> [TerrainRegion: String] {
    let manifest = try JSONDecoder().decode(
      DownloadManifest.self,
      from: Data(contentsOf: manifestURL)
    )
    let root = publicRoot.hasSuffix("/") ? publicRoot : publicRoot + "/"
    return manifest.assetPacks.reduce(into: [:]) { keys, pack in
      guard let region = TerrainRegion.allCases.first(where: { $0.downloadIdentifier == pack.id }),
        pack.url.hasPrefix(root)
      else { return }
      keys[region] = String(pack.url.dropFirst(root.count))
    }
  }

  /// Fetches the currently published download manifest when this machine has no local copy.
  ///
  /// Without it, a run from a fresh checkout would have nothing to update and would `create` a
  /// manifest that resets every pack to version 0.
  private func adoptPublishedManifest(at manifestURL: URL) async {
    guard !FileManager.default.fileExists(atPath: manifestURL.path) else { return }
    guard
      let publishedURL = URL(string: downloadBaseURL)?
        .deletingLastPathComponent()
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

  /// Where the given region's archive is written.
  nonisolated func archiveURL(for region: TerrainRegion) -> URL {
    outputLocation
      .appendingPathComponent(region.downloadIdentifier)
      .appendingPathExtension(Self.archiveExtension)
  }

  /// Whether an archive already exists and is no older than the files it was built from.
  private func archiveIsCurrent(_ archiveURL: URL, for region: TerrainRegion) -> Bool {
    isFile(at: archiveURL, noOlderThan: [region.remoteFilename, region.digestFilename])
  }

  /// The payload's SHA-256, from the file beside it, which is written first unless one no older
  /// than the payload is there.
  private func payloadDigest(for region: TerrainRegion) throws -> String {
    let digestURL = outputLocation.appendingPathComponent(region.digestFilename)
    if isFile(at: digestURL, noOlderThan: [region.remoteFilename]) {
      return try String(contentsOf: digestURL, encoding: .utf8)
    }

    let payloadURL = outputLocation.appendingPathComponent(region.remoteFilename)
    let digest = try TerrainPayloadDigest.hexDigest(ofFileAt: payloadURL)
    try Data(digest.utf8).write(to: digestURL, options: .atomic)
    logger.info("Wrote the SHA-256 of \(region.remoteFilename): \(digest)")
    return digest
  }

  /// Whether `url` exists and was modified no earlier than each named file in the output
  /// directory.
  private func isFile(at url: URL, noOlderThan filenames: [String]) -> Bool {
    guard let date = modificationDate(of: url) else { return false }
    return filenames.allSatisfy { filename in
      modificationDate(of: outputLocation.appendingPathComponent(filename)).map { date >= $0 }
        ?? false
    }
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
  private func writePackManifest(for region: TerrainRegion, payloadDigest: String) throws -> URL {
    let manifest = PackManifest(
      assetPackID: region.downloadIdentifier,
      downloadPolicy: .init(prefetch: .init(installationEventTypes: Self.installationEventTypes)),
      fileSelectors: [.init(file: region.remoteFilename), .init(file: region.digestFilename)],
      platforms: ["iOS"],
      userInfo: ["regionID": region.rawValue, Self.payloadDigestKey: payloadDigest]
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
      try Self.runBAPackage(arguments, workingDirectory: outputLocation)
    }.value
  }

  // MARK: - Nested Types

  /// One region's asset pack as this run left it.
  struct PackagedRegion: Sendable {
    let region: TerrainRegion
    let archiveURL: URL
    /// SHA-256 of the payload the archive holds.
    let payloadDigest: String
    /// Whether this run rebuilt the archive, as opposed to reusing a current one.
    let isRebuilt: Bool
  }

  /// The parts of the download manifest `ba-package` writes that say where each pack is served.
  private struct DownloadManifest: Decodable {
    let assetPacks: [AssetPack]

    struct AssetPack: Decodable {
      let id: String
      let url: String
      let userInfo: [String: String]?
    }
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
