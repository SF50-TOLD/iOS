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
/// Poll the ``state`` property to track loading progress:
///
/// ```swift
/// let loader = NavDataLoader(modelContainer: container)
/// Task {
///     while true {
///         switch await loader.state {
///         case .downloading(let progress):
///             print("Downloading: \(progress ?? 0)")
///         case .loading(let progress):
///             print("Importing: \(progress ?? 0)")
///         default:
///             break
///         }
///         try? await Task.sleep(for: .seconds(0.25))
///     }
/// }
/// let result = try await loader.load()
/// ```
///
/// ## See Also
///
/// - ``NavDataLoaderViewModel``
/// - ``State``
@ModelActor
actor NavDataLoader {
  private static let dataURLTemplate =
    "https://github.com/SF50-TOLD/NavDataDistribution/releases/download/%1$@/%1$@.plist.lzma"

  /// Maximum number of rows inserted per save.
  ///
  /// Each save holds the store's write lock for its full commit, growing the
  /// WAL and stalling other store users (the widget process, background
  /// readers), so transactions are kept small and frequent.
  private static let saveBatchRowLimit = 2000

  /// Pause between batch saves so other store users can interleave.
  private static let interBatchPause: Duration = .milliseconds(50)

  var state: State = .idle

  private let decoder = PropertyListDecoder()

  private let logger = Logger(
    subsystem: "codes.tim.SF50-TOLD",
    category: "NavDataLoader"
  )

  private var navaidLookup: [String: SF50_Shared.Navaid] = [:]

  private var dataURL: URL {
    URL(string: String(format: Self.dataURLTemplate, "\(Cycle.effective)"))!
  }

  func load() async throws -> LoadResult {
    state = .downloading(progress: 0)
    let data = try await download { self.state = .downloading(progress: $0) }

    state = .extracting(progress: nil)
    let nasr = try decompress(data: data)

    // The replacement data is fully decoded, so the old dataset can go
    try await resetData()

    // Load navaids first so they're available for leg relationships
    try await loadNavaids(nasr.navaids ?? [])

    // Combined progress tracking across both loading phases
    state = .loading(progress: 0)
    let totalItems = nasr.airports.count + nasr.obstacles.count

    try await loadAirports(nasr.airports) { airportsProcessed in
      self.state = .loading(progress: Float(airportsProcessed) / Float(totalItems))
    }

    let airportCount = nasr.airports.count
    try await loadObstacles(nasr.obstacles) { obstaclesProcessed in
      self.state = .loading(progress: Float(airportCount + obstaclesProcessed) / Float(totalItems))
    }

    try writeCycles(nasr.cycles)

    state = .finished
    return LoadResult(
      cycles: nasr.cycles,
      ourAirportsLastUpdated: nasr.ourAirportsLastUpdated
    )
  }

  /// Deletes all persisted ``Cycle`` records on the loader's background context.
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

  private func download(progress: (Float) -> Void) async throws -> Data {
    try await withRetry(logger: logger, label: "nav data") {
      let session = URLSession(configuration: .ephemeral)
      let (bytes, response) = try await session.bytes(from: self.dataURL)
      guard let response = response as? HTTPURLResponse else { throw Errors.badResponse(response) }
      if response.statusCode == 404 { throw Errors.cycleNotAvailable }
      guard response.statusCode == 200 else { throw Errors.badResponse(response) }

      var compressedData = Data(capacity: Int(response.expectedContentLength))
      for try await byte in bytes {
        compressedData.append(byte)
        let completed = compressedData.count
        if completed.isMultiple(of: 8192) {
          let downloadProgress = Double(completed) / Double(response.expectedContentLength)
          progress(Float(downloadProgress))
        }
      }

      return compressedData
    }
  }

  private func decompress(data: Data) throws -> AirportDataCodable {
    // swiftlint:disable:next legacy_objc_type
    let data = try (data as NSData).decompressed(using: .lzma)
    return try decoder.decode(AirportDataCodable.self, from: data as Data)
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
        try await Task.sleep(for: Self.interBatchPause)
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
      try await Task.sleep(for: Self.interBatchPause)
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
      try await Task.sleep(for: Self.interBatchPause)
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
      try await Task.sleep(for: Self.interBatchPause)
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
  enum State {
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
