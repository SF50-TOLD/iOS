import Foundation
import Logging
import SF50_Shared

/// Publishes the on-device NOTAM model as an asset pack, run headless via environment variables.
///
/// Environment variables:
/// - `NOTAM_MODEL_HEADLESS`: Set to "1" to enable NOTAM model headless mode
/// - `NOTAM_MODEL_SKIP_UPLOAD`: Set to "1" to package and update the manifest without uploading
///
/// The app is sandboxed, so the model folder is read from the app's Documents directory, at
/// `NOTAMModel/notam-model`: copy the converted model folder there first. The download manifest is
/// the terrain packs' local copy, `Terrain/terrain-asset-packs-ios.json`.
enum NOTAMModelHeadlessProcessor {
  private static let env = ProcessInfo.processInfo.environment

  /// Returns true if NOTAM model headless mode is enabled via environment variable.
  static func shouldRunHeadless() -> Bool {
    env["NOTAM_MODEL_HEADLESS"] == "1"
  }

  /// Publishes the model.
  /// - Returns: Exit code (0 for success, 1 for error)
  static func run() async -> Int32 {
    let logger = Logger(label: "NOTAMModelHeadlessProcessor")
    guard
      let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
      let config = R2Uploader.Config.fromBundle()
    else {
      logger.error("Could not locate Documents, or R2 isn't configured")
      return 1
    }

    let terrainDirectory = documents.appendingPathComponent("Terrain", isDirectory: true)
    let publisher = NOTAMModelPackPublisher(
      outputLocation: documents.appendingPathComponent("NOTAMModel", isDirectory: true),
      manifestURL: terrainDirectory.appendingPathComponent(
        AssetPackPublisher.downloadManifestFilename
      ),
      publicRoot: config.publicURL,
      releaseStamp: Date.now.formatted(
        Date.ISO8601FormatStyle(dateSeparator: .omitted, timeSeparator: .omitted)
      ),
      logger: logger
    )

    do {
      try FileManager.default.createDirectory(
        at: terrainDirectory,
        withIntermediateDirectories: true
      )
      guard let archive = try await publisher.publish() else { return 0 }
      guard env["NOTAM_MODEL_SKIP_UPLOAD"] != "1" else {
        logger.notice("Skipping upload; the archive and manifest are in Documents")
        return 0
      }
      try await upload(archive, using: publisher, config: config, logger: logger)
      logger.notice("NOTAM model published")
      return 0
    } catch {
      let reason = (error as? any LocalizedError)?.failureReason.map { " \($0)" } ?? ""
      logger.error("Publishing failed: \(error.localizedDescription)\(reason)")
      return 1
    }
  }

  /// Uploads the archive under the key the manifest names, unless it's already there, then the
  /// manifest: publishing the manifest is what releases the pack to devices.
  private static func upload(
    _ archive: URL,
    using publisher: NOTAMModelPackPublisher,
    config: R2Uploader.Config,
    logger: Logger
  ) async throws {
    let uploader = R2Uploader(config: config, logger: logger)
    let key = try await publisher.publishedKey()
    if try await uploader.publishedSize(ofObjectAt: key) == nil {
      try await uploader.uploadFile(at: archive, key: key)
    } else {
      logger.notice("\(key) is already published")
    }
    try await uploader.uploadFile(
      at: publisher.manifestURL,
      key: AssetPackPublisher.downloadManifestFilename
    )
  }
}
