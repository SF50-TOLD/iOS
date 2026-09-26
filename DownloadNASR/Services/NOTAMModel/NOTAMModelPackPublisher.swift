import Foundation
import Logging
import SF50_Shared

/// Errors that can occur while publishing the NOTAM model as an asset pack.
enum NOTAMModelPackPublisherError: LocalizedError {
  case modelMissing(URL)
  case packMissingFromManifest

  var errorDescription: String? {
    String(localized: "The NOTAM model couldn’t be published.")
  }

  var failureReason: String? {
    switch self {
      case .modelMissing(let folder):
        String(localized: "No NOTAM model folder (with notam-model.json) at “\(folder.path)”.")
      case .packMissingFromManifest:
        String(localized: "The download manifest has no NOTAM model pack under the public URL.")
    }
  }
}

/// Packages the on-device NOTAM model as a self-hosted Background Assets asset pack and adds it
/// to the download manifest the terrain packs are published in.
///
/// The app's `BAManifestURL` names one manifest, so the model pack (`NOTAMModelPack.id`) sits in
/// it beside the terrain packs, and this updates only its own entry. The model folder goes into the
/// pack under `NOTAMModelPack.folderPath` with its digest (`NOTAMModelDigest`) beside the files,
/// which the app checks before loading the model.
///
/// As with terrain, a published archive is never replaced: a changed model is published under a
/// key stamped with this run, and its version in the manifest rises, which is what makes installed
/// copies update. The pack's `userInfo` carries the folder's digest, so an unchanged model is left
/// alone.
actor NOTAMModelPackPublisher {

  // MARK: - Type Properties

  /// Key prefix the model packs are published under.
  static let packKeyPrefix = "notam-model-packs"

  /// Name of the model folder in ``outputLocation``, which is also its path in the pack.
  private static let folderName = NOTAMModelPack.folderPath

  private static let archiveName = "notam-model.aar"
  private static let payloadDigestKey = "payloadSHA256"
  private static let installationEventTypes = ["firstInstallation", "subsequentUpdate"]

  // MARK: - Instance Properties

  /// Directory holding the model folder, where the archive is written.
  let outputLocation: URL

  /// The local copy of the download manifest shared with the terrain packs.
  let manifestURL: URL

  /// Public URL of the bucket the packs are published to.
  let publicRoot: String

  /// Base URL this run's pack is served from; `ba-package` appends the pack's ID.
  let downloadBaseURL: String

  private let logger: Logger

  // MARK: - Initializers

  /// - Parameters:
  ///   - outputLocation: Directory holding the `notam-model` folder, where the archive is written.
  ///   - manifestURL: The local copy of the download manifest shared with the terrain packs.
  ///   - publicRoot: Public URL of the bucket the pack is published to.
  ///   - releaseStamp: Names this run's pack apart from every earlier run's.
  ///   - logger: Logger for status messages and errors.
  init(
    outputLocation: URL,
    manifestURL: URL,
    publicRoot: String,
    releaseStamp: String,
    logger: Logger
  ) {
    self.outputLocation = outputLocation
    self.manifestURL = manifestURL
    let trimmedRoot = publicRoot.hasSuffix("/") ? String(publicRoot.dropLast()) : publicRoot
    self.publicRoot = trimmedRoot
    downloadBaseURL = "\(trimmedRoot)/\(Self.packKeyPrefix)/\(releaseStamp)"
    self.logger = logger
  }

  // MARK: - Methods

  /// Packages the model and brings the download manifest's entry for it up to date.
  ///
  /// - Returns: The archive, when the manifest now points at a new one, or `nil` when the published
  ///   pack already holds this model.
  func publish() async throws -> URL? {
    let folder = outputLocation.appendingPathComponent(Self.folderName, isDirectory: true)
    guard
      FileManager.default.fileExists(atPath: folder.appendingPathComponent("notam-model.json").path)
    else { throw NOTAMModelPackPublisherError.modelMissing(folder) }

    let digest = try await writeDigest(of: folder)
    if let root = URL(string: publicRoot) {
      await AssetPackPublisher.adoptPublishedManifest(
        at: manifestURL,
        publicRoot: root,
        logger: logger
      )
    }
    guard try publishedDigest() != digest else {
      logger.notice("The published NOTAM model pack already holds this model")
      return nil
    }

    let archive = try await packageArchive(digest: digest, modelVersion: modelVersion(in: folder))
    try await updateDownloadManifest(with: archive)
    return archive
  }

  /// The object key the download manifest names for the model pack.
  func publishedKey() throws -> String {
    let manifest = try JSONDecoder().decode(
      DownloadManifest.self,
      from: Data(contentsOf: manifestURL)
    )
    let root = publicRoot + "/"
    guard let pack = manifest.assetPacks.first(where: { $0.id == NOTAMModelPack.id }),
      pack.url.hasPrefix(root)
    else { throw NOTAMModelPackPublisherError.packMissingFromManifest }
    return String(pack.url.dropFirst(root.count))
  }

  private func writeDigest(of folder: URL) async throws -> String {
    let digest = try await Task.detached(priority: .userInitiated) {
      try NOTAMModelDigest.hexDigest(ofFolderAt: folder)
    }.value
    let digestURL = outputLocation.appendingPathComponent(NOTAMModelPack.digestPath)
    try Data(digest.utf8).write(to: digestURL, options: .atomic)
    logger.notice("NOTAM model digest: \(digest)")
    return digest
  }

  private func modelVersion(in folder: URL) throws -> String {
    let manifest = try JSONDecoder().decode(
      ModelManifest.self,
      from: Data(contentsOf: folder.appendingPathComponent("notam-model.json"))
    )
    return manifest.modelVersion ?? "unversioned"
  }

  /// The digest the published manifest's model pack carries, or `nil` when it has none.
  private func publishedDigest() throws -> String? {
    guard FileManager.default.fileExists(atPath: manifestURL.path) else { return nil }
    let manifest = try JSONDecoder().decode(
      DownloadManifest.self,
      from: Data(contentsOf: manifestURL)
    )
    return manifest.assetPacks.first { $0.id == NOTAMModelPack.id }?.userInfo?[
      Self.payloadDigestKey
    ]
  }

  private func packageArchive(digest: String, modelVersion: String) async throws -> URL {
    let packManifest = PackManifest(
      assetPackID: NOTAMModelPack.id,
      downloadPolicy: .init(prefetch: .init(installationEventTypes: Self.installationEventTypes)),
      fileSelectors: [.init(directory: Self.folderName)],
      platforms: ["iOS"],
      userInfo: [Self.payloadDigestKey: digest, "modelVersion": modelVersion]
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let packManifestURL = outputLocation.appendingPathComponent(
      "Manifest-\(NOTAMModelPack.id).json"
    )
    try encoder.encode(packManifest).write(to: packManifestURL)
    defer { try? FileManager.default.removeItem(at: packManifestURL) }

    let archive = outputLocation.appendingPathComponent(Self.archiveName)
    try? FileManager.default.removeItem(at: archive)
    let output = try await run([packManifestURL.path, "-o", archive.path])
    logger.notice("Packaged the NOTAM model (\(modelVersion)): \(output)")
    return archive
  }

  /// Adds or bumps the model pack's entry, leaving every other pack's alone.
  ///
  /// `download-manifest update` accepts only asset-pack paths ending in `.json`, so the archive is
  /// passed through a hard link of that name (a symbolic link would report its own size).
  private func updateDownloadManifest(with archive: URL) async throws {
    let alias = outputLocation.appendingPathComponent("\(NOTAMModelPack.id).json")
    try? FileManager.default.removeItem(at: alias)
    try FileManager.default.linkItem(at: archive, to: alias)
    defer { try? FileManager.default.removeItem(at: alias) }

    let output = try await run([
      "download-manifest", "update", manifestURL.path, "--asset-pack-paths", alias.path,
      "--ios", "--download-base-url", downloadBaseURL
    ])
    logger.notice("Updated the NOTAM model pack in the download manifest: \(output)")
  }

  private func run(_ arguments: [String]) async throws -> String {
    let outputLocation = outputLocation
    return try await Task.detached(priority: .userInitiated) {
      try AssetPackPublisher.runBAPackage(arguments, workingDirectory: outputLocation)
    }.value
  }

  // MARK: - Nested Types

  /// The parts of the download manifest this reads.
  private struct DownloadManifest: Decodable {
    let assetPacks: [AssetPack]

    struct AssetPack: Decodable {
      let id: String
      let url: String
      let userInfo: [String: String]?
    }
  }

  /// The part of the model's `notam-model.json` this reads.
  private struct ModelManifest: Decodable {
    let modelVersion: String?
  }

  /// The asset-pack manifest schema `ba-package` reads.
  private struct PackManifest: Encodable {
    let assetPackID: String
    let downloadPolicy: DownloadPolicy
    let fileSelectors: [DirectorySelector]
    let platforms: [String]
    let userInfo: [String: String]

    struct DownloadPolicy: Encodable {
      let prefetch: Prefetch

      struct Prefetch: Encodable {
        let installationEventTypes: [String]
      }
    }

    struct DirectorySelector: Encodable {
      let directory: String
    }
  }
}
