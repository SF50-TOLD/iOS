import Algorithms
import CoreLocation
import Foundation
import Observation
import os
import SF50_Shared
import SwiftData
import SwiftNASR

/// Downloads and imports navigation data from the GitHub repository.
///
/// `NavDataLoader` is a `@ModelActor` that handles the complete navigation data
/// update pipeline:
///
/// 1. **Download**: Fetches compressed data from GitHub
/// 2. **Decompress**: Extracts LZMA-compressed property list
/// 3. **Import**: Populates SwiftData with `Airport`, `Runway`, `Procedure`,
///    `ProcedureSegment`, `Leg`, and `Obstacle` models
///
/// It writes into an empty store of its own — the next *generation* of the
/// dataset — and never touches the one in use. Nothing switches to what it wrote
/// until the import finishes and the result is found to hold airports, so an
/// import that fails, or is killed when the pilot swipes the app away, costs the
/// pilot nothing. That is why there is no step here that clears anything first.
///
/// ## Data Source
///
/// Navigation data is pre-processed and published as GitHub release assets at:
/// `github.com/SF50-TOLD/NavDataDistribution`, with one compressed property
/// list per publication cycle.
///
/// The data combines FAA NASR (National Airspace System Resources) with
/// OurAirports for international coverage, CIFP for departure procedures,
/// and DOF for obstacles.
///
/// ## Data Format
///
/// Navigation data is stored as an LZMA-compressed property list containing:
///
/// - Airport records (location ID, name, coordinates, elevation, etc.)
/// - Runway records (heading, length, distances, gradient)
/// - Departure procedures (SIDs with legs, altitude restrictions, and leg types)
/// - Approach procedures (with missed approach legs and altitude restrictions)
/// - Obstacles (from FAA Digital Obstacle File)
/// - NASR, CIFP, and DOF cycle information
/// - OurAirports last update timestamp
///
/// ## Usage
///
/// Create a loader with the model container and call ``load()``:
///
/// ```swift
/// let loader = NavDataLoader(modelContainer: container)
/// let result = try await loader.load()
/// ```
///
/// ## Progress Tracking
///
/// Iterate ``stateUpdates()`` to follow the loader's progress. The loader pushes
/// each new ``State`` into the stream:
///
/// ```swift
/// let loader = NavDataLoader(modelContainer: container)
/// let updates = await loader.stateUpdates()
/// Task {
///     for await state in updates {
///         switch state {
///         case .downloading(let progress):
///             print("Downloading: \(progress ?? 0)")
///         case .loading(let progress):
///             print("Importing: \(progress ?? 0)")
///         default:
///             break
///         }
///     }
/// }
/// let result = try await loader.load()
/// ```
///
/// ## Executor Constraints
///
/// A `@ModelActor`'s serial executor is its `NSManagedObjectContext`'s dispatch
/// queue, and SwiftData enqueues jobs onto that executor with
/// `-[NSManagedObjectContext performBlockAndWait:]`. Enqueueing therefore blocks
/// the *calling* thread until the executor is free, so every caller — the main
/// actor included — stalls for as long as this actor stays busy. Two rules
/// follow, and both are load-bearing for main-thread responsiveness:
///
/// - No long-running work may occupy the executor without suspending. CPU-bound
///   work belongs in a `nonisolated` `@concurrent` function the actor `await`s,
///   and persistence work is split into bounded batches separated by `await`.
/// - Progress is pushed out through ``stateUpdates()`` rather than pulled by
///   callers, because yielding into an `AsyncStream` is nonblocking whereas
///   reading an isolated property is an enqueue.
///
/// ## See Also
///
/// - ``NavDataLoaderViewModel``
/// - ``State``
actor NavDataLoader {
  private static let dataURLTemplate =
    "https://github.com/SF50-TOLD/NavDataDistribution/releases/download/%1$@/%1$@.plist.lzma"

  /// Smallest change in download progress worth pushing to consumers.
  ///
  /// The session reports progress once per received chunk, which is far finer
  /// than a progress indicator can show; coarsening it keeps consumers from
  /// waking hundreds of times a second for changes they cannot render.
  private static let progressReportingStep: Float = 0.005

  private(set) var state: State = .idle {
    didSet { stateContinuation?.yield(state) }
  }

  private let logger = Logger(
    subsystem: "codes.tim.SF50-TOLD",
    category: "NavDataLoader"
  )
  private let signposter = OSSignposter(
    subsystem: "codes.tim.SF50-TOLD",
    category: "NavDataLoader"
  )

  private let writer: NavDataStoreWriter
  private var stateContinuation: AsyncStream<State>.Continuation?

  private var dataURL: URL {
    URL(string: String(format: Self.dataURLTemplate, "\(Cycle.effective)"))!
  }

  /// Creates a loader writing into `modelContainer`.
  ///
  /// - Parameter modelContainer: A container whose nav-data store accepts writes, holding the
  ///   generation this import is producing.
  init(modelContainer: ModelContainer) {
    writer = .init(modelContainer: modelContainer)
  }

  /// Inflates the LZMA payload and decodes it, off this actor's executor.
  ///
  /// Both steps are CPU-bound and touch no `modelContext`, so they run on the
  /// concurrent pool while the actor suspends. Mapping the compressed file
  /// keeps it out of the app's dirty memory, leaving only the inflated
  /// property list resident.
  @concurrent
  nonisolated private static func decompress(fileAt url: URL) async throws -> AirportDataCodable {
    let compressed = try Data(contentsOf: url, options: .mappedIfSafe)
    // swiftlint:disable:next legacy_objc_type
    let inflated = try (compressed as NSData).decompressed(using: .lzma)
    return try PropertyListDecoder().decode(AirportDataCodable.self, from: inflated as Data)
  }

  /// Downloads the payload to a temporary file, off this actor's executor.
  ///
  /// A transfer run on the actor's executor would occupy the backing
  /// `NSManagedObjectContext`'s queue for the length of the download, so
  /// anything enqueueing onto this actor would wait on the network.
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
      label: "nav data",
      reportingTo: continuation
    )

    guard let response = response as? HTTPURLResponse else {
      try? FileManager.default.removeItem(at: fileURL)
      throw Errors.badResponse(response)
    }
    guard response.statusCode == 200 else {
      try? FileManager.default.removeItem(at: fileURL)
      throw response.statusCode == 404 ? Errors.cycleNotAvailable : Errors.badResponse(response)
    }

    return fileURL
  }

  /// A stream of ``State`` values, starting with the loader's current state and
  /// finishing when ``load()`` returns or throws.
  ///
  /// Only one stream is live at a time; a second call finishes the previous one.
  func stateUpdates() -> AsyncStream<State> {
    stateContinuation?.finish()
    let (stream, continuation) = AsyncStream.makeStream(
      of: State.self,
      bufferingPolicy: .bufferingNewest(1)
    )
    continuation.yield(state)
    stateContinuation = continuation
    return stream
  }

  func load() async throws -> LoadResult {
    defer { stateContinuation?.finish() }

    state = .downloading(progress: 0)
    let payload = try await timing("download") {
      try await download { self.reportDownloadProgress($0) }
    }
    defer { try? FileManager.default.removeItem(at: payload) }

    state = .extracting(progress: nil)
    let nasr = try await timing("decode") { try await Self.decompress(fileAt: payload) }

    state = .loading(progress: 0)
    try await timing("write") { try await write(nasr) }

    state = .finished
    return LoadResult(
      cycles: nasr.cycles,
      ourAirportsLastUpdated: nasr.ourAirportsLastUpdated
    )
  }

  /// Runs an import phase, logging how long it took and bracketing it with a
  /// signpost interval.
  ///
  /// The import's cost is spread across downloading, decoding, and several
  /// persistence phases whose relative weights shift with the dataset's size
  /// and with how the writes are batched, so a slowdown is only diagnosable if
  /// each phase reports its own duration. The log line answers “how long” after
  /// the fact; the signpost puts the same phase on an Instruments timeline,
  /// where it can be lined up against the allocations, disk writes, and thread
  /// states that explain why.
  private func timing<T>(
    _ label: String,
    _ phase: () async throws -> T
  ) async rethrows -> T {
    let interval = signposter.beginInterval(
      "nav data phase",
      id: signposter.makeSignpostID(),
      "\(label, privacy: .public)"
    )
    defer { signposter.endInterval("nav data phase", interval) }

    let start = ContinuousClock.now
    let result = try await phase()
    logger.info("nav data \(label) took \(start.duration(to: .now), privacy: .public)")
    return result
  }

  private func reportDownloadProgress(_ progress: Float) {
    guard case .downloading(let reported) = state else { return }
    if let reported, abs(progress - reported) < Self.progressReportingStep { return }
    state = .downloading(progress: progress)
  }

  /// Writes the decoded dataset, mirroring the writer's progress onto this actor's state.
  ///
  /// The write runs as a child task so this actor stays free to drain its progress; the stream
  /// closes when the write settles, ending the loop.
  private func write(_ data: AirportDataCodable) async throws {
    let (progressUpdates, continuation) = AsyncStream<Float>.makeStream(
      of: Float.self,
      bufferingPolicy: .bufferingNewest(1)
    )

    async let written: Void = writer.write(data, reportingTo: continuation)
    for await completed in progressUpdates { state = .loading(progress: completed) }

    try await written
  }

  /// Downloads the payload, forwarding the transfer's progress to `progress`.
  ///
  /// The transfer runs as a child task so this actor stays free to drain its
  /// progress; the stream closes when the transfer settles, ending the loop.
  private func download(progress: (Float) -> Void) async throws -> URL {
    let (progressUpdates, continuation) = AsyncStream<Float>.makeStream(
      of: Float.self,
      bufferingPolicy: .bufferingNewest(1)
    )

    async let downloaded = Self.fetch(from: dataURL, logger: logger, reportingTo: continuation)
    for await completed in progressUpdates { progress(completed) }

    return try await downloaded
  }

  /// Current state of the loading process.
  ///
  /// ## Cases
  ///
  /// - ``idle``: Not started
  /// - ``downloading(progress:)``: Downloading from GitHub (0.0-1.0)
  /// - ``extracting(progress:)``: Decompressing LZMA data
  /// - ``loading(progress:)``: Importing into SwiftData (0.0-1.0)
  /// - ``finished``: Complete
  enum State: Sendable {
    case idle
    case downloading(progress: Float?)
    case extracting(progress: Float?)
    case loading(progress: Float?)
    case finished
  }

  /// Errors that can occur during data loading.
  enum Errors: Swift.Error {
    /// The current AIRAC cycle data is not yet available on GitHub.
    case cycleNotAvailable

    /// The server returned an unexpected response.
    case badResponse(_ response: URLResponse)
  }

  /// Loaded data including cycle information and OurAirports update date.
  struct LoadResult {
    /// Cycle information for all data sources.
    let cycles: AirportDataCodable.DataCycles
    /// Date when OurAirports data was last updated.
    let ourAirportsLastUpdated: Date?
  }
}
