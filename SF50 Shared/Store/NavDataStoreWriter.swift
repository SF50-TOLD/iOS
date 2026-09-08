public import Foundation
public import SwiftData

import Algorithms
import CoreLocation
import NavData

/// Writes a decoded navigation dataset into a SwiftData store.
///
/// This is the only implementation of the shape a nav-data store takes, and both things that
/// produce one use it: the app, importing a downloaded property list, and the macOS tool that
/// publishes a store built ahead of time. Two implementations would drift, and the difference
/// between them would only show up in a cockpit.
///
/// The store it writes is expected to be empty. A dataset is replaced by writing a new generation
/// beside the one in use, never by clearing rows out of it.
///
/// ## Executor Constraints
///
/// A `@ModelActor`'s serial executor is its `NSManagedObjectContext`'s dispatch queue, and SwiftData
/// enqueues jobs onto that executor with `-[NSManagedObjectContext performBlockAndWait:]`.
/// Enqueueing therefore blocks the *calling* thread until the executor is free, so every caller —
/// the main actor included — stalls for as long as this actor stays busy. Persistence work is
/// split into bounded batches separated by `await` so it never occupies the executor without
/// suspending.
@ModelActor
public actor NavDataStoreWriter {
  /// Maximum number of rows written per save.
  ///
  /// Each save holds the store's write lock for its full commit, so the import is split into
  /// bounded transactions rather than one that spans the whole dataset. The bound is generous
  /// because the writer works through its own persistent store coordinator against a WAL-journaled
  /// store, where readers are never blocked by a write in flight; the only cost a long transaction
  /// imposes is on this actor's own executor, which a smaller bound would trade for many more
  /// commits.
  private static let saveBatchRowLimit = 10000

  private var navaidLookup: [String: Navaid] = [:]

  /// Writes an entire dataset, reporting how far through it has got.
  ///
  /// Progress is pushed into a stream rather than handed to a callback, because a callback would
  /// have to cross back into the caller's isolation on an actor whose executor this work occupies.
  ///
  /// - Parameters:
  ///   - data: The decoded dataset to write.
  ///   - continuation: Yielded a fraction from 0 to 1 as airports and obstacles are written, and
  ///     finished when the dataset is fully written.
  public func write(
    _ data: AirportDataCodable,
    reportingTo continuation: AsyncStream<Float>.Continuation
  ) async throws {
    defer { continuation.finish() }
    let progress = { continuation.yield($0) }

    // Navaids come first so they are available for leg relationships.
    try await loadNavaids(data.navaids ?? [])

    let totalItems = data.airports.count + data.obstacles.count
    try await loadAirports(data.airports) { airportsProcessed in
      progress(Float(airportsProcessed) / Float(totalItems))
    }

    let airportCount = data.airports.count
    try await loadObstacles(data.obstacles) { obstaclesProcessed in
      progress(Float(airportCount + obstaclesProcessed) / Float(totalItems))
    }

    try writeCycles(data.cycles)
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

  private func loadNavaids(_ navaids: [NavaidCodable]) async throws {
    navaidLookup.removeAll()
    for batch in navaids.chunks(ofCount: Self.saveBatchRowLimit) {
      for navaidData in batch {
        let navaid = Navaid(
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

  /// Inserts an airport and its runways, procedures, segments, and legs.
  ///
  /// - Returns: The number of rows inserted, so callers can bound save batches
  ///   by row count.
  private func lookupNavaid(_ legData: AirportDataCodable.LegCodable) -> Navaid? {
    guard let id = legData.recommendedNavaidIdentifier,
      let icao = legData.recommendedNavaidICAO
    else { return nil }
    return navaidLookup["\(id):\(icao)"]
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
    var runwayMap = [String: Runway]()

    for runwayData in airport.runways {
      // Create threshold coordinate if both lat/lon are available
      var thresholdCoordinate: CLLocationCoordinate2D?
      if let lat = runwayData.thresholdLatitude,
        let lon = runwayData.thresholdLongitude
      {
        thresholdCoordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
      }

      let runway = Runway(
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
}
