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
/// Navigation data is pre-processed and hosted at:
/// `github.com/SF50-TOLD/Airport-Data`
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
    "https://github.com/SF50-TOLD/Airport-Data/blob/main/3.0/%@.plist.lzma?raw=true"

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

    // Load navaids first so they're available for leg relationships
    loadNavaids(nasr.navaids ?? [])

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

    state = .finished
    return LoadResult(
      cycles: nasr.cycles,
      ourAirportsLastUpdated: nasr.ourAirportsLastUpdated
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
    let data = try (data as NSData).decompressed(using: .lzma)  // swiftlint:disable:this legacy_objc_type
    return try decoder.decode(AirportDataCodable.self, from: data as Data)
  }

  private func loadAirports(
    _ airports: [AirportDataCodable.AirportCodable],
    progress: (Int) -> Void
  ) async throws {
    try resetData()

    var processed = 0

    for batch in airports.chunks(ofCount: 500) {
      for airport in batch {
        addAirport(airport)
      }

      try modelContext.save()

      processed += batch.count
      progress(processed)
      try await Task.sleep(for: .milliseconds(50))
    }
  }

  private func loadObstacles(
    _ obstacles: [AirportDataCodable.ObstacleCodable],
    progress: (Int) -> Void
  ) async throws {
    var processed = 0

    for batch in obstacles.chunks(ofCount: 5000) {
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
      try await Task.sleep(for: .milliseconds(50))
    }
  }

  private func lookupNavaid(_ legData: AirportDataCodable.LegCodable) -> SF50_Shared.Navaid? {
    guard let id = legData.recommendedNavaidIdentifier,
      let icao = legData.recommendedNavaidICAO
    else { return nil }
    return navaidLookup["\(id):\(icao)"]
  }

  private func loadNavaids(_ navaids: [NavaidCodable]) {
    navaidLookup.removeAll()
    for navaidData in navaids {
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
  }

  private func resetData() throws {
    try modelContext.delete(model: SF50_Shared.Airport.self)
    try modelContext.delete(model: SF50_Shared.Runway.self)
    try modelContext.delete(model: SF50_Shared.Procedure.self)
    try modelContext.delete(model: SF50_Shared.ProcedureSegment.self)
    try modelContext.delete(model: SF50_Shared.Leg.self)
    try modelContext.delete(model: SF50_Shared.Navaid.self)
    try modelContext.delete(model: SF50_Shared.Obstacle.self)
    try modelContext.delete(model: NOTAM.self)
    try modelContext.save()
  }

  private func addAirport(_ airport: AirportDataCodable.AirportCodable) {
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
        isTurf: runwayData.isTurf,
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
    guard !runwayMap.isEmpty else { return }

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

      for segmentData in procedureData.segments ?? [] {
        let segment = ProcedureSegment(
          runwayNames: segmentData.runwayNames ?? [],
          procedure: procedure
        )
        modelContext.insert(segment)

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
        }
      }
    }
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
