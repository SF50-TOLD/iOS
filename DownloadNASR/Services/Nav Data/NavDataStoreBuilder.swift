import CryptoKit
import Foundation
import Logging
import NavData
import SF50_Shared
import StreamingLZMAXZ
import SwiftData

/// Builds the SwiftData store the app downloads, from the dataset it already publishes.
///
/// The app spends minutes assembling this store on the pilot's device, once a cycle, before it can
/// be used at all. Building it here instead turns that into a download.
///
/// It is written through `NavDataStoreWriter`, the same code the app's own import
/// path runs, so the store this produces and the store the app would have built are the same store.
struct NavDataStoreBuilder {
  private let logger: Logger

  /// Creates a builder logging to `logger`.
  ///
  /// - Parameter logger: Where to report progress.
  init(logger: Logger) {
    self.logger = logger
  }

  /// Builds a store from a published property list, and describes it.
  ///
  /// - Parameters:
  ///   - plist: The `<cycle>.plist` this cycle's dataset was encoded to.
  ///   - cycle: The cycle the dataset is effective for.
  ///   - outputLocation: The directory to write the store and its manifest into.
  /// - Returns: The files written.
  func build(fromPlistAt plist: URL, cycle: String, outputLocation: URL) async throws -> Output {
    let data = try PropertyListDecoder().decode(
      AirportDataCodable.self,
      from: try Data(contentsOf: plist, options: .mappedIfSafe)
    )
    logger.info("Decoded \(data.airports.count) airports and \(data.obstacles.count) obstacles")

    let workspace = outputLocation.appending(path: "build-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: workspace) }

    let assembled = try await assemble(data, in: workspace)
    let store = outputLocation.appending(path: "\(cycle).store")

    // VACUUM INTO writes one fully materialized file. Copying the store instead would leave its
    // most recent rows in the write-ahead log beside it, and a store shipped without that sidecar
    // opens perfectly and reads as empty.
    try compact(assembled, into: store)

    let counts = try rowCounts(of: store)
    guard counts.airports == data.airports.count else {
      throw Errors.storeIsIncomplete(expected: data.airports.count, found: counts.airports)
    }

    let compressed = try compress(store, cycle: cycle, in: outputLocation)
    logger.notice(
      """
      Built \(compressed.lastPathComponent): \(bytes(of: store) / 1_048_576) MB uncompressed, \
      \(bytes(of: compressed) / 1_048_576) MB compressed, \(counts.airports) airports, \
      \(counts.obstacles) obstacles
      """
    )

    return .init(
      store: compressed,
      manifest: try writeManifest(
        for: compressed,
        cycle: cycle,
        cycles: data.cycles,
        counts: counts,
        ourAirportsLastUpdated: data.ourAirportsLastUpdated,
        outputLocation: outputLocation
      )
    )
  }

  /// Compresses the store the way every other published payload is compressed.
  private func compress(_ store: URL, cycle: String, in outputLocation: URL) throws -> URL {
    let compressed = outputLocation.appending(path: "\(cycle).store.lzma")
    try Data(contentsOf: store, options: .mappedIfSafe).xzCompressed().write(to: compressed)
    return compressed
  }

  private func bytes(of url: URL) -> Int {
    (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
  }

  /// Writes the dataset into a store of its own.
  private func assemble(_ data: AirportDataCodable, in workspace: URL) async throws -> URL {
    let layout = StoreLayout(baseDirectory: workspace)

    // Opened through the same pair of configurations the app reads with. SwiftData records the
    // whole container's schema in every store, so one written by a container of a different shape
    // reads back as needing migration — which a store opened read-only cannot do.
    let container = try AppStore.makeWritableContainer(layout: layout, generation: 0)
    let (progress, continuation) = AsyncStream<Float>.makeStream(
      of: Float.self,
      bufferingPolicy: .bufferingNewest(1)
    )

    async let written: Void = NavDataStoreWriter(modelContainer: container)
      .write(data, reportingTo: continuation)
    for await completed in progress {
      logger.debug("Writing store: \(Int(completed * 100))%")
    }
    try await written

    return layout.navStoreURL(generation: 0)
  }

  private func compact(_ source: URL, into destination: URL) throws {
    try? FileManager.default.removeItem(at: destination)

    let process = Process()
    process.executableURL = URL(filePath: "/usr/bin/sqlite3")
    process.arguments = [source.path, "VACUUM INTO '\(destination.path)';"]
    try process.run()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
      throw Errors.compactionFailed(status: process.terminationStatus)
    }
  }

  /// Opens the built store exactly as the app does, and counts what is in it.
  ///
  /// Read-only, through the app's own configurations: a store this binary can write but the app
  /// cannot open read-only is the failure worth catching here rather than on a device.
  private func rowCounts(of store: URL) throws -> NavDataStoreManifest.Counts {
    let workspace = store.deletingLastPathComponent().appending(path: "verify-\(UUID().uuidString)")
    let layout = StoreLayout(baseDirectory: workspace)
    defer { try? FileManager.default.removeItem(at: workspace) }

    try layout.createDirectories()
    try FileManager.default.copyItem(at: store, to: layout.navStoreURL(generation: 0))

    let context = ModelContext(try AppStore.makeContainer(layout: layout, generation: 0))
    return .init(
      airports: try context.fetchCount(FetchDescriptor<Airport>()),
      runways: try context.fetchCount(FetchDescriptor<Runway>()),
      obstacles: try context.fetchCount(FetchDescriptor<Obstacle>())
    )
  }

  private func writeManifest(
    for store: URL,
    cycle: String,
    cycles: AirportDataCodable.DataCycles,
    counts: NavDataStoreManifest.Counts,
    ourAirportsLastUpdated: Date?,
    outputLocation: URL
  ) throws -> URL {
    let payload = try Data(contentsOf: store, options: .mappedIfSafe)
    let digest = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()

    guard let nasr = cycles.nasr else { throw Errors.cycleIsUndated }
    let manifest = NavDataStoreManifest(
      cycle: cycle,
      effective: nasr.effective,
      expires: nasr.expires,
      schemaFingerprint: NavDataSchema.fingerprint,
      schemaVersion: latestSchemaVersion,
      store: .init(
        filename: store.lastPathComponent,
        bytes: payload.count,
        sha256: digest
      ),
      counts: counts,
      ourAirportsLastUpdated: ourAirportsLastUpdated
    )

    let url = outputLocation.appending(path: "\(cycle).json")
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    try encoder.encode(manifest).write(to: url)
    return url
  }

  /// Reasons a store could not be built.
  enum Errors: Swift.Error, LocalizedError {
    /// Compacting the store into a single file failed.
    case compactionFailed(status: Int32)

    /// The built store holds fewer airports than the dataset it was built from.
    case storeIsIncomplete(expected: Int, found: Int)

    /// The dataset carries no NASR cycle, so the store cannot say when it is effective.
    case cycleIsUndated

    var errorDescription: String? { "Couldn’t build the navigation data store." }

    var failureReason: String? {
      switch self {
        case .compactionFailed(let status):
          "sqlite3 exited with status \(status) while compacting the store."
        case .storeIsIncomplete(let expected, let found):
          "The store holds \(found) airports; the dataset has \(expected)."
        case .cycleIsUndated:
          "The dataset carries no NASR cycle to date the store with."
      }
    }
  }

  /// The file a built store is written to, and its manifest.
  struct Output {
    /// The compressed store.
    let store: URL

    /// The manifest describing it.
    let manifest: URL
  }
}
