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
@ModelActor
actor NavDataLoader {
  private static let dataURLTemplate =
    "https://github.com/SF50-TOLD/NavDataDistribution/releases/download/%1$@/%1$@.plist.lzma"

  /// Maximum number of rows written per save.
  ///
  /// Each save holds the store's write lock for its full commit, so the import
  /// is split into bounded transactions rather than one that spans the whole
  /// dataset. The bound is generous because the importer writes through its
  /// own persistent store coordinator against a WAL-journaled store, where
  /// readers — the main context and the widget process — are never blocked by
  /// a write in flight; the only cost a long transaction imposes is on this
  /// actor's own executor, which a smaller bound would trade for many more
  /// commits.
  private static let saveBatchRowLimit = 10000

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

  private var navaidLookup: [String: SF50_Shared.Navaid] = [:]
  private var stateContinuation: AsyncStream<State>.Continuation?

  private var dataURL: URL {
    URL(string: String(format: Self.dataURLTemplate, "\(Cycle.effective)"))!
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

    // The replacement data is fully decoded, so the old dataset can go
    try await timing("reset") { try await resetData() }

    // Load navaids first so they're available for leg relationships
    try await timing("navaids") { try await loadNavaids(nasr.navaids ?? []) }

    // Combined progress tracking across both loading phases
    state = .loading(progress: 0)
    let totalItems = nasr.airports.count + nasr.obstacles.count

    try await timing("airports") {
      try await loadAirports(nasr.airports) { airportsProcessed in
        self.state = .loading(progress: Float(airportsProcessed) / Float(totalItems))
      }
    }

    let airportCount = nasr.airports.count
    try await timing("obstacles") {
      try await loadObstacles(nasr.obstacles) { obstaclesProcessed in
        self.state = .loading(
          progress: Float(airportCount + obstaclesProcessed) / Float(totalItems)
        )
      }
    }

    try writeCycles(nasr.cycles)

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

  /// Deletes all persisted `Cycle` records on the loader's background context.
  ///
  /// Performed off the main thread so it never contends with the main
  /// `NSManagedObjectContext` for the persistent store coordinator.
  func clearCycles() throws {
    try modelContext.delete(model: Cycle.self)
    try modelContext.save()
  }

  private func writeCycles(_ cycles: AirportDataCodable.DataCycles) throws {
    insertCycle(cycles.nasr, source: .nasr)
    insertCycle(cycles.cifp, source: .cifp)
    insertCycle(cycles.dof, source: .dof)
    try modelContext.save()
  }

  private func insertCycle(
    _ info: AirportDataCodable.CycleInfo?,
    source: CycleDataSource
  ) {
    guard let info else { return }
    modelContext.insert(
      Cycle(
        dataSource: source,
        name: info.name,
        effective: info.effective,
        expires: info.expires
      )
    )
  }

  private func reportDownloadProgress(_ progress: Float) {
    guard case .downloading(let reported) = state else { return }
    if let reported, abs(progress - reported) < Self.progressReportingStep { return }
    state = .downloading(progress: progress)
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

  private func loadAirports(
    _ airports: [AirportDataCodable.AirportCodable],
    progress: (Int) -> Void
  ) async throws {
    var processed = 0,
      rowsSinceLastSave = 0

    // An airport carries nested runway/procedure/segment/leg inserts, so
    // batches are bounded by total inserted rows rather than airport count.
    for airport in airports {
      rowsSinceLastSave += addAirport(airport)
      processed += 1

      if rowsSinceLastSave >= Self.saveBatchRowLimit {
        try modelContext.save()
        rowsSinceLastSave = 0
        progress(processed)
        await Task.yield()
      }
    }

    if modelContext.hasChanges {
      try modelContext.save()
      progress(processed)
    }
  }

  private func loadObstacles(
    _ obstacles: [AirportDataCodable.ObstacleCodable],
    progress: (Int) -> Void
  ) async throws {
    var processed = 0

    for batch in obstacles.chunks(ofCount: Self.saveBatchRowLimit) {
      for obstacleData in batch {
        let obstacle = Obstacle(
          heightMSL: .init(value: Double(obstacleData.heightFtMSL), unit: .feet),
          latitude: .init(value: obstacleData.latitude, unit: .degrees),
          longitude: .init(value: obstacleData.longitude, unit: .degrees)
        )
        modelContext.insert(obstacle)
      }

      try modelContext.save()

      processed += batch.count
      progress(processed)
      await Task.yield()
    }
  }

  private func lookupNavaid(_ legData: AirportDataCodable.LegCodable) -> SF50_Shared.Navaid? {
    guard let id = legData.recommendedNavaidIdentifier,
      let icao = legData.recommendedNavaidICAO
    else { return nil }
    return navaidLookup["\(id):\(icao)"]
  }

  private func loadNavaids(_ navaids: [NavaidCodable]) async throws {
    navaidLookup.removeAll()
    for batch in navaids.chunks(ofCount: Self.saveBatchRowLimit) {
      for navaidData in batch {
        let navaid = SF50_Shared.Navaid(
          identifier: navaidData.identifier,
          icaoRegion: navaidData.icaoRegion,
          type: navaidData.type,
          latitude: .init(value: navaidData.latitude, unit: .degrees),
          longitude: .init(value: navaidData.longitude, unit: .degrees),
          elevation: navaidData.elevationFt.map { .init(value: $0, unit: .feet) }
        )
        modelContext.insert(navaid)
        navaidLookup["\(navaidData.identifier):\(navaidData.icaoRegion)"] = navaid
      }
      try modelContext.save()
      await Task.yield()
    }
  }

  /// Deletes the previous dataset in bounded batches, one entity type at a time.
  ///
  /// Child entities are deleted before their parents so each delete touches
  /// only its own table instead of fanning out through cascade rules.
  private func resetData() async throws {
    try await deleteAll(NOTAM.self)
    try await deleteAll(SF50_Shared.Leg.self)
    try await deleteAll(SF50_Shared.ProcedureSegment.self)
    try await deleteAll(SF50_Shared.Procedure.self)
    try await deleteAll(SF50_Shared.Runway.self)
    try await deleteAll(SF50_Shared.Airport.self)
    try await deleteAll(SF50_Shared.Navaid.self)
    try await deleteAll(SF50_Shared.Obstacle.self)
  }

  /// Deletes every row of `model` in `saveBatchRowLimit`-sized transactions.
  ///
  /// SwiftData's bulk `delete(model:)` removes all rows in a single transaction
  /// that holds the store's write lock for its full duration, stalling
  /// concurrent main-context reads long enough to trip an app-hang report.
  /// Deleting in bounded transactions with a pause between them keeps each lock
  /// hold short so other store users can interleave, mirroring the insert path.
  private func deleteAll<Model: PersistentModel>(_: Model.Type) async throws {
    var descriptor = FetchDescriptor<Model>()
    descriptor.fetchLimit = Self.saveBatchRowLimit

    while case let batch = try modelContext.fetch(descriptor), !batch.isEmpty {
      for object in batch { modelContext.delete(object) }
      try modelContext.save()
      await Task.yield()
    }
  }

  /// Inserts an airport and its runways, procedures, segments, and legs.
  ///
  /// - Returns: The number of rows inserted, so callers can bound save batches
  ///   by row count.
  private func addAirport(_ airport: AirportDataCodable.AirportCodable) -> Int {
    let dataSource = DataSource(rawValue: airport.dataSource) ?? .NASR
    let timeZone = airport.timeZone.flatMap { TimeZone(identifier: $0) }

    let record = Airport(
      recordID: airport.recordID,
      locationID: airport.locationID,
      ICAO_ID: airport.ICAO_ID,
      name: airport.name,
      city: airport.city,
      dataSource: dataSource,
      latitude: .init(value: airport.latitude, unit: .degrees),
      longitude: .init(value: airport.longitude, unit: .degrees),
      elevation: .init(value: airport.elevation, unit: .meters),
      variation: .init(value: airport.variation, unit: .degrees),
      timeZone: timeZone
    )

    // Create a map to find reciprocal runways
    var runwayMap = [String: SF50_Shared.Runway]()

    for runwayData in airport.runways {
      // Create threshold coordinate if both lat/lon are available
      var thresholdCoordinate: CLLocationCoordinate2D?
      if let lat = runwayData.thresholdLatitude,
        let lon = runwayData.thresholdLongitude
      {
        thresholdCoordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
      }

      let runway = SF50_Shared.Runway(
        name: runwayData.name,
        elevation: runwayData.elevation.map { .init(value: $0, unit: .meters) },
        trueHeading: .init(value: runwayData.trueHeading, unit: .degrees),
        gradient: runwayData.gradient,
        length: .init(value: runwayData.length, unit: .meters),
        width: runwayData.width.map { .init(value: $0, unit: .meters) },
        takeoffRun: runwayData.takeoffRun.map { .init(value: $0, unit: .meters) },
        takeoffDistance: runwayData.takeoffDistance.map { .init(value: $0, unit: .meters) },
        landingDistance: runwayData.landingDistance.map { .init(value: $0, unit: .meters) },
        surfaceType: runwayData.decodedSurfaceType,
        thresholdCoordinate: thresholdCoordinate,
        thresholdCrossingHeight: runwayData.thresholdCrossingHeight.map {
          .init(value: $0, unit: .meters)
        },
        glidepathAngle: runwayData.glidepathAngle.map { .init(value: $0, unit: .degrees) },
        displacedThresholdDistance: runwayData.displacedThresholdDistance.map {
          .init(value: $0, unit: .meters)
        },
        airport: record
      )
      runwayMap[runwayData.name] = runway
    }

    // Only insert the airport and runways if we have runways
    guard !runwayMap.isEmpty else { return 0 }

    var insertedRows = 1 + runwayMap.count

    modelContext.insert(record)
    for runway in runwayMap.values {
      modelContext.insert(runway)
    }

    // Set reciprocal runway names
    for runwayData in airport.runways {
      if let runway = runwayMap[runwayData.name] {
        runway.reciprocalName = runwayData.reciprocalName
      }
    }

    // Load procedures (departures and approaches)
    for procedureData in airport.procedures ?? [] {
      let procedureType = Procedure.ProcedureType(rawValue: procedureData.type) ?? .departure
      let procedure = Procedure(
        type: procedureType,
        identifier: procedureData.identifier,
        name: procedureData.name,
        runwayName: procedureData.runwayName,
        requiredClimbGradientFtPerNM: procedureData.requiredClimbGradientFtPerNM,
        airport: record
      )
      modelContext.insert(procedure)
      insertedRows += 1

      for segmentData in procedureData.segments ?? [] {
        let segment = ProcedureSegment(
          runwayNames: segmentData.runwayNames ?? [],
          procedure: procedure
        )
        modelContext.insert(segment)
        insertedRows += 1

        for (index, legData) in segmentData.legs.enumerated() {
          let altitudeRestriction = legData.altitudeRestriction.map {
            AltitudeRestriction(from: $0)
          }
          let navaid = lookupNavaid(legData)
          let leg = Leg(
            identifier: legData.identifier,
            latitude: legData.latitude.map { .init(value: $0, unit: .degrees) },
            longitude: legData.longitude.map { .init(value: $0, unit: .degrees) },
            altitudeRestriction: altitudeRestriction,
            legType: legData.legType,
            sequenceIndex: index,
            segment: segment,
            navaid: navaid,
            dmeDistance: legData.dmeDistanceNM.map { .init(value: $0, unit: .nauticalMiles) },
            theta: legData.thetaDeg.map { .init(value: $0, unit: .degrees) }
          )
          modelContext.insert(leg)
          insertedRows += 1
        }
      }
    }

    return insertedRows
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
