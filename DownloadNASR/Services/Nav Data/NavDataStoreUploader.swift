import Foundation
import Logging
import SF50_Shared

/// Publishes a built nav-data store and its manifest to R2.
///
/// The app asks for a cycle by name, so the two files are keyed by cycle rather than by anything
/// mutable. The manifest goes up **after** the store: a client that finds a manifest can rely on the
/// store it names being there, whereas the reverse ordering would advertise a file still uploading.
struct NavDataStoreUploader {
  /// Where published nav data lives in the bucket.
  static let keyPrefix = "navdata"

  private let logger: Logger

  /// Creates an uploader logging to `logger`.
  ///
  /// - Parameter logger: Where to report progress.
  init(logger: Logger) {
    self.logger = logger
  }

  /// The public URL a published cycle's manifest is served from.
  ///
  /// - Parameters:
  ///   - cycle: The cycle to address.
  ///   - publicURL: The bucket's public base URL.
  /// - Returns: The manifest's address.
  static func manifestURL(cycle: String, publicURL: String) -> String {
    "\(publicURL.trimmedTrailingSlash)/\(keyPrefix)/\(cycle).json"
  }

  /// Uploads a cycle's store and manifest.
  ///
  /// - Parameters:
  ///   - output: The files ``NavDataStoreBuilder`` produced.
  ///   - cycle: The cycle they belong to.
  /// - Throws: ``R2Error`` if the bucket is misconfigured or an upload fails.
  func upload(_ output: NavDataStoreBuilder.Output, cycle: String) async throws {
    guard let config = R2Uploader.Config.fromBundle() else { throw R2Error.invalidConfig }
    let uploader = R2Uploader(config: config, logger: logger)

    try await uploader.uploadFile(
      at: output.store,
      key: "\(Self.keyPrefix)/\(output.store.lastPathComponent)"
    ) { fraction in
      logger.debug("Uploading store: \(Int(fraction * 100))%")
    }

    // Only now is the manifest true.
    try await uploader.uploadFile(
      at: output.manifest,
      key: "\(Self.keyPrefix)/\(output.manifest.lastPathComponent)"
    )

    logger.notice(
      "Published cycle \(cycle) to \(Self.manifestURL(cycle: cycle, publicURL: config.publicURL))"
    )
  }
}

extension String {
  fileprivate var trimmedTrailingSlash: String {
    hasSuffix("/") ? String(dropLast()) : self
  }
}
