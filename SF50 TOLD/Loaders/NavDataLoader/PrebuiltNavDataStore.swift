import CryptoKit
import Foundation
import SF50_Shared
import SwiftNASR
import os

/// Fetches a nav-data store that was built ahead of time, instead of assembling one on the device.
///
/// The app used to spend minutes inserting a decoded property list into SwiftData before it could be
/// used at all. The same store is now built on a Mac once per cycle and published, so this downloads
/// and expands it — the work that remains is a transfer and a decompression.
///
/// Every step here is allowed to fail. A cycle that was never published, a store built against a
/// different schema, a truncated download: each falls back to importing the property list, which is
/// still published and still works. That is what makes this an optimization rather than a dependency.
actor PrebuiltNavDataStore {
  /// Where published stores are served from.
  ///
  /// The same bucket the terrain payloads use.
  private static let manifestURLTemplate =
    "https://pub-becd30c7b4e24860bee04cbbab788fb3.r2.dev/navdata/%@.json"

  /// How many cycles back to look before giving up and importing instead.
  ///
  /// One is enough to cover a publish that failed on the day a cycle took effect; more than that and
  /// the data would be old enough that importing the current cycle is the better answer.
  private static let cyclesToWalkBack = 2

  private let logger = Logger(
    subsystem: "codes.tim.SF50-TOLD",
    category: "PrebuiltNavDataStore"
  )

  nonisolated private static func fetch(
    from url: URL,
    logger: Logger,
    reportingTo continuation: AsyncStream<Float>.Continuation
  ) async throws -> URL {
    defer { continuation.finish() }
    let (fileURL, response) = try await downloadWithRetry(
      from: url,
      configuration: .ephemeral,
      logger: logger,
      label: "prebuilt nav data",
      reportingTo: continuation
    )
    guard (response as? HTTPURLResponse)?.statusCode == 200 else {
      try? FileManager.default.removeItem(at: fileURL)
      throw Errors.noPublishedCycle
    }
    return fileURL
  }

  /// Hashes the downloaded payload, off this actor.
  @concurrent
  nonisolated private static func digest(of payload: URL) async throws -> String {
    let data = try Data(contentsOf: payload, options: .mappedIfSafe)
    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  /// Expands the compressed store, off this actor.
  @concurrent
  nonisolated private static func expand(_ payload: URL, to destination: URL) async throws {
    let compressed = try Data(contentsOf: payload, options: .mappedIfSafe)
    // swiftlint:disable:next legacy_objc_type
    let store = try (compressed as NSData).decompressed(using: .lzma)
    try (store as Data).write(to: destination, options: .atomic)
  }

  /// Downloads the newest published store this build can read, and expands it to `destination`.
  ///
  /// Cycles are asked for by name and walked backwards, because a manifest states the window it is
  /// effective for and a mutable "latest" pointer could not. A cycle whose publish failed therefore
  /// costs the pilot the previous cycle's data rather than four weeks of no update at all.
  ///
  /// - Parameters:
  ///   - destination: Where to write the expanded store.
  ///   - continuation: Yielded progress as the transfer and expansion proceed.
  /// - Returns: The manifest of the cycle installed.
  /// - Throws: ``Errors`` if nothing publishable could be found or read.
  func download(
    to destination: URL,
    reportingTo continuation: AsyncStream<NavDataLoader.State>.Continuation
  ) async throws -> NavDataStoreManifest {
    let manifest = try await newestReadableManifest()

    continuation.yield(.downloading(progress: 0))
    let payload = try await fetchStore(described: manifest, reportingTo: continuation)
    defer { try? FileManager.default.removeItem(at: payload) }

    continuation.yield(.extracting(progress: nil))
    try await Self.expand(payload, to: destination)

    return manifest
  }

  /// The newest published cycle whose store this build's schema can read.
  ///
  /// Checked before anything is downloaded, let alone opened: SwiftData answers a near-miss schema
  /// by migrating rather than by refusing, so a store opened first would be silently, slowly
  /// migrated where a clean fall back to the import path was wanted.
  private func newestReadableManifest() async throws -> NavDataStoreManifest {
    var cycle: SwiftNASR.Cycle? = .effective
    for _ in 0..<Self.cyclesToWalkBack {
      guard let candidate = cycle else { break }
      cycle = candidate.previous

      guard let manifest = await manifest(for: "\(candidate)") else { continue }
      guard manifest.schemaFingerprint == NavDataSchema.fingerprint,
        manifest.schemaVersion == latestSchemaVersion
      else {
        logger.notice(
          """
          Cycle \(manifest.cycle, privacy: .public) was built for a different store shape; \
          importing instead
          """
        )
        throw Errors.schemaMismatch(
          published: manifest.schemaFingerprint,
          expected: NavDataSchema.fingerprint
        )
      }
      return manifest
    }
    throw Errors.noPublishedCycle
  }

  /// The manifest for one cycle, or `nil` if it was never published.
  private func manifest(for cycle: String) async -> NavDataStoreManifest? {
    guard let url = URL(string: String(format: Self.manifestURLTemplate, cycle)) else { return nil }
    do {
      let (data, response) = try await URLSession(configuration: .ephemeral).data(from: url)
      guard (response as? HTTPURLResponse)?.statusCode == 200 else {
        logger.info("No published store for cycle \(cycle, privacy: .public)")
        return nil
      }
      let decoder = JSONDecoder()
      decoder.dateDecodingStrategy = .iso8601
      return try decoder.decode(NavDataStoreManifest.self, from: data)
    } catch {
      logger.notice("Couldn’t read the manifest for \(cycle, privacy: .public): \(error)")
      return nil
    }
  }

  /// Downloads the store a manifest describes, and checks it against the digest published for it.
  private func fetchStore(
    described manifest: NavDataStoreManifest,
    reportingTo continuation: AsyncStream<NavDataLoader.State>.Continuation
  ) async throws -> URL {
    let base = URL(string: String(format: Self.manifestURLTemplate, manifest.cycle))!
      .deletingLastPathComponent()
    let url = base.appending(path: manifest.store.filename)

    let (progressUpdates, progress) = AsyncStream<Float>.makeStream(
      of: Float.self,
      bufferingPolicy: .bufferingNewest(1)
    )
    async let downloaded = Self.fetch(from: url, logger: logger, reportingTo: progress)
    for await completed in progressUpdates { continuation.yield(.downloading(progress: completed)) }

    let payload = try await downloaded
    guard try await Self.digest(of: payload) == manifest.store.sha256 else {
      try? FileManager.default.removeItem(at: payload)
      throw Errors.digestMismatch
    }
    return payload
  }

  /// Reasons a prebuilt store could not be used.
  enum Errors: Swift.Error {
    /// No cycle in range had a manifest this build could read.
    case noPublishedCycle

    /// The published store was built for a different shape of store than this build reads.
    case schemaMismatch(published: String, expected: String)

    /// The download did not match the digest its manifest published.
    case digestMismatch
  }
}
