import CoreLocation
import Foundation
import RealModule
import SwiftData
import Testing

@testable import SF50_Shared

struct ProcedureTerrainPathTests {

  // MARK: - ProcedureTerrainPath

  @Test
  func emptyPoints() {
    let path = ProcedureTerrainPath(corridorWidthNM: 0.25, points: [])
    #expect(path.points.isEmpty)
    #expect(path.totalDistanceNM.isApproximatelyEqual(to: 0, absoluteTolerance: 0.001))
    #expect(path.coordinates.isEmpty)
  }

  @Test
  func totalDistanceFromLastPoint() {
    let points = [
      ProcedureTerrainPath.Point(
        coordinate: CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0),
        distanceNM: 0,
        track: .init(value: 0, unit: .degrees),
        aircraftAltitudeFt: 100,
        altitudeRestriction: nil,
        fixName: nil,
        terrainElevationFt: nil,
        maxObstacleHeightFt: nil
      ),
      ProcedureTerrainPath.Point(
        coordinate: CLLocationCoordinate2D(latitude: 37.1, longitude: -122.0),
        distanceNM: 5.5,
        track: .init(value: 0, unit: .degrees),
        aircraftAltitudeFt: 1700,
        altitudeRestriction: nil,
        fixName: "FIX1",
        terrainElevationFt: 200,
        maxObstacleHeightFt: 350
      )
    ]
    let path = ProcedureTerrainPath(corridorWidthNM: 0.25, points: points)
    #expect(path.totalDistanceNM.isApproximatelyEqual(to: 5.5, absoluteTolerance: 0.001))
    #expect(path.coordinates.count == 2)
  }

  // MARK: - terrainDataAvailable

  @Test
  func terrainDataAvailableWhenAllPointsHaveTerrain() {
    let points = [
      ProcedureTerrainPath.Point(
        coordinate: CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0),
        distanceNM: 0,
        track: .init(value: 0, unit: .degrees),
        aircraftAltitudeFt: 100,
        altitudeRestriction: nil,
        fixName: nil,
        terrainElevationFt: 50,
        maxObstacleHeightFt: nil
      ),
      ProcedureTerrainPath.Point(
        coordinate: CLLocationCoordinate2D(latitude: 37.1, longitude: -122.0),
        distanceNM: 5.5,
        track: .init(value: 0, unit: .degrees),
        aircraftAltitudeFt: 1700,
        altitudeRestriction: nil,
        fixName: nil,
        terrainElevationFt: 200,
        maxObstacleHeightFt: nil
      )
    ]
    let path = ProcedureTerrainPath(corridorWidthNM: 0.25, points: points)
    #expect(path.terrainDataAvailable)
  }

  @Test
  func terrainDataUnavailableWhenAnyPointMissingTerrain() {
    let points = [
      ProcedureTerrainPath.Point(
        coordinate: CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0),
        distanceNM: 0,
        track: .init(value: 0, unit: .degrees),
        aircraftAltitudeFt: 100,
        altitudeRestriction: nil,
        fixName: nil,
        terrainElevationFt: 50,
        maxObstacleHeightFt: nil
      ),
      ProcedureTerrainPath.Point(
        coordinate: CLLocationCoordinate2D(latitude: 37.1, longitude: -122.0),
        distanceNM: 5.5,
        track: .init(value: 0, unit: .degrees),
        aircraftAltitudeFt: 1700,
        altitudeRestriction: nil,
        fixName: nil,
        terrainElevationFt: nil,
        maxObstacleHeightFt: nil
      )
    ]
    let path = ProcedureTerrainPath(corridorWidthNM: 0.25, points: points)
    #expect(!path.terrainDataAvailable)
  }

  // MARK: - obstacleDataAvailable

  @Test
  func obstacleDataAvailableWhenAllPointsInUS() {
    let points = [
      ProcedureTerrainPath.Point(
        coordinate: CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0),
        distanceNM: 0,
        track: .init(value: 0, unit: .degrees),
        aircraftAltitudeFt: 100,
        altitudeRestriction: nil,
        fixName: nil,
        terrainElevationFt: nil,
        maxObstacleHeightFt: nil
      ),
      ProcedureTerrainPath.Point(
        coordinate: CLLocationCoordinate2D(latitude: 37.1, longitude: -122.0),
        distanceNM: 5.5,
        track: .init(value: 0, unit: .degrees),
        aircraftAltitudeFt: 1700,
        altitudeRestriction: nil,
        fixName: nil,
        terrainElevationFt: nil,
        maxObstacleHeightFt: nil
      )
    ]
    let path = ProcedureTerrainPath(corridorWidthNM: 0.25, points: points)
    #expect(path.obstacleDataAvailable)
  }

  @Test
  func obstacleDataUnavailableWhenPointOutsideUS() {
    let points = [
      ProcedureTerrainPath.Point(
        coordinate: CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0),
        distanceNM: 0,
        track: .init(value: 0, unit: .degrees),
        aircraftAltitudeFt: 100,
        altitudeRestriction: nil,
        fixName: nil,
        terrainElevationFt: nil,
        maxObstacleHeightFt: nil
      ),
      ProcedureTerrainPath.Point(
        coordinate: CLLocationCoordinate2D(latitude: 51.5, longitude: -0.1),  // London
        distanceNM: 5.5,
        track: .init(value: 0, unit: .degrees),
        aircraftAltitudeFt: 1700,
        altitudeRestriction: nil,
        fixName: nil,
        terrainElevationFt: nil,
        maxObstacleHeightFt: nil
      )
    ]
    let path = ProcedureTerrainPath(corridorWidthNM: 0.25, points: points)
    #expect(!path.obstacleDataAvailable)
  }
}

struct ProcedureTerrainPathGeneratorTests {

  // MARK: - Shared Constants

  private let takeoffPoint = CLLocationCoordinate2D(latitude: 37.3626, longitude: -121.9291)
  private let magneticVariation = Measurement<UnitAngle>(value: -14, unit: .degrees)
  private let takeoffAltitudeFt = 62.0
  private var climbProfile: ClimbProfile { Helper.createTestClimbProfile() }

  /// Creates an in-memory ModelContainer with the full schema.
  private func makeModelContainer() throws -> ModelContainer {
    let schema = Schema([
      Airport.self,
      Runway.self,
      NOTAM.self,
      Scenario.self,
      Cycle.self,
      Obstacle.self,
      Procedure.self,
      ProcedureSegment.self,
      Leg.self,
      Navaid.self
    ])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: [config])
  }

  /// Generates a simple departure ProcedurePath for test use.
  private func makeTestProcedurePath() -> ProcedurePath? {
    let fixes = [
      Helper.createTestLeg(
        identifier: "FIX1",
        latitude: 37.38,
        longitude: -121.95,
        legType: .initialFix,
        sequenceIndex: 0
      ),
      Helper.createTestLeg(
        identifier: "FIX2",
        latitude: 37.40,
        longitude: -122.00,
        legType: .trackToFix(course: .init(value: 300, unit: .degrees)),
        sequenceIndex: 1
      )
    ]
    return ProcedurePathGenerator(
      climbProfile: climbProfile,
      schedule: .init(segments: [.init(profile: .enroute(antiIce: false))]),
      magneticVariation: magneticVariation
    ).departurePath(
      from: fixes,
      takeoffPoint: takeoffPoint,
      takeoffPointAltitudeFt: takeoffAltitudeFt
    )
  }

  // MARK: - Empty Path

  @Test
  func emptyPathReturnsEmptyTerrainPath() async throws {
    let container = try makeModelContainer()
    let terrainService = TerrainService()
    let emptyPath = ProcedurePath(points: [])

    let generator = ProcedureTerrainPathGenerator(
      modelContainer: container,
      terrainService: terrainService
    )
    let result = await generator.generate(from: emptyPath)

    #expect(result.points.isEmpty)
    #expect(result.totalDistanceNM.isApproximatelyEqual(to: 0, absoluteTolerance: 0.001))
  }

  // MARK: - Point Count Preservation

  @Test
  func outputPointCountMatchesInput() async throws {
    let container = try makeModelContainer()
    let terrainService = TerrainService()
    let path = try #require(makeTestProcedurePath())

    let generator = ProcedureTerrainPathGenerator(
      modelContainer: container,
      terrainService: terrainService
    )
    let result = await generator.generate(from: path)

    #expect(result.points.count == path.points.count)
  }

  // MARK: - Flight Profile Preservation

  @Test
  func aircraftAltitudeAndDistancePreserved() async throws {
    let container = try makeModelContainer()
    let terrainService = TerrainService()
    let path = try #require(makeTestProcedurePath())

    let generator = ProcedureTerrainPathGenerator(
      modelContainer: container,
      terrainService: terrainService
    )
    let result = await generator.generate(from: path)

    for (i, terrainPoint) in result.points.enumerated() {
      let originalPoint = path.points[i]
      #expect(
        terrainPoint.distanceNM.isApproximatelyEqual(
          to: originalPoint.distanceNM,
          absoluteTolerance: 0.001
        )
      )
      #expect(
        terrainPoint.aircraftAltitudeFt.isApproximatelyEqual(
          to: originalPoint.altitudeFt,
          absoluteTolerance: 0.001
        )
      )
      #expect(
        terrainPoint.coordinate.latitude.isApproximatelyEqual(
          to: originalPoint.coordinate.latitude,
          absoluteTolerance: 0.0001
        )
      )
      #expect(
        terrainPoint.coordinate.longitude.isApproximatelyEqual(
          to: originalPoint.coordinate.longitude,
          absoluteTolerance: 0.0001
        )
      )
    }
  }

  @Test
  func fixNamesAndAltitudeRestrictionsPreserved() async throws {
    let container = try makeModelContainer()
    let terrainService = TerrainService()
    let path = try #require(makeTestProcedurePath())

    let generator = ProcedureTerrainPathGenerator(
      modelContainer: container,
      terrainService: terrainService
    )
    let result = await generator.generate(from: path)

    for (i, terrainPoint) in result.points.enumerated() {
      let originalPoint = path.points[i]
      #expect(terrainPoint.fixName == originalPoint.fixName)
      #expect(terrainPoint.altitudeRestriction == originalPoint.altitudeRestriction)
    }
  }

  // MARK: - Terrain (No Data Loaded)

  @Test
  func noTerrainDataInUnloadedRegionReturnsNilElevations() async throws {
    let container = try makeModelContainer()
    let terrainService = TerrainService()  // no regions loaded
    let path = try #require(makeTestProcedurePath())

    // Path is in North America (a TerrainRegion exists but isn't loaded)
    let generator = ProcedureTerrainPathGenerator(
      modelContainer: container,
      terrainService: terrainService
    )
    let result = await generator.generate(from: path)

    for point in result.points {
      #expect(point.terrainElevationFt == nil)
    }
  }

  // MARK: - Ocean Fill

  @Test
  func oceanPointsGetZeroTerrainElevation() async throws {
    let container = try makeModelContainer()
    let terrainService = TerrainService()  // no regions loaded

    // Create a path over open ocean (mid-Atlantic, outside all TerrainRegion bounding boxes)
    let oceanPoint = ProcedurePath.Point(
      coordinate: CLLocationCoordinate2D(latitude: 30.0, longitude: -45.0),
      distanceNM: 0,
      altitudeFt: 5000,
      altitudeRestriction: nil,
      fixName: nil
    )
    let oceanPath = ProcedurePath(points: [oceanPoint])

    let generator = ProcedureTerrainPathGenerator(
      modelContainer: container,
      terrainService: terrainService
    )
    let result = await generator.generate(from: oceanPath)

    #expect(result.points.count == 1)
    #expect(result.points[0].terrainElevationFt == 0)
  }

  // MARK: - Obstacles

  @Test
  func noObstaclesReturnsNilHeights() async throws {
    let container = try makeModelContainer()
    let terrainService = TerrainService()
    let path = try #require(makeTestProcedurePath())

    let generator = ProcedureTerrainPathGenerator(
      modelContainer: container,
      terrainService: terrainService
    )
    let result = await generator.generate(from: path)

    for point in result.points {
      #expect(point.maxObstacleHeightFt == nil)
    }
  }

  @Test
  func obstacleWithinCorridorIsDetected() async throws {
    let container = try makeModelContainer()
    let terrainService = TerrainService()
    let path = try #require(makeTestProcedurePath())

    // Insert an obstacle right on the path (at the midpoint coordinate)
    let midIndex = path.points.count / 2
    let midCoord = path.points[midIndex].coordinate
    let context = ModelContext(container)
    let obstacle = Obstacle(
      heightMSL: .init(value: 500, unit: .feet),
      latitude: .init(value: midCoord.latitude, unit: .degrees),
      longitude: .init(value: midCoord.longitude, unit: .degrees)
    )
    context.insert(obstacle)
    try context.save()

    let generator = ProcedureTerrainPathGenerator(
      modelContainer: container,
      terrainService: terrainService
    )
    let result = await generator.generate(from: path)

    // At least one point should have a non-nil obstacle height
    let hasObstacle = result.points.contains { $0.maxObstacleHeightFt != nil }
    #expect(hasObstacle)

    // The detected obstacle height should match what we inserted
    let obstaclePoint = result.points.first { $0.maxObstacleHeightFt != nil }!
    #expect(
      obstaclePoint.maxObstacleHeightFt!.isApproximatelyEqual(
        to: 500,
        absoluteTolerance: 1
      )
    )
  }

  @Test
  func obstacleOutsideCorridorIsNotDetected() async throws {
    let container = try makeModelContainer()
    let terrainService = TerrainService()
    let path = try #require(makeTestProcedurePath())

    // Insert an obstacle far from the path (1 degree away)
    let context = ModelContext(container)
    let obstacle = Obstacle(
      heightMSL: .init(value: 500, unit: .feet),
      latitude: .init(value: 38.5, unit: .degrees),
      longitude: .init(value: -120.0, unit: .degrees)
    )
    context.insert(obstacle)
    try context.save()

    let generator = ProcedureTerrainPathGenerator(
      modelContainer: container,
      terrainService: terrainService
    )
    let result = await generator.generate(from: path)

    for point in result.points {
      #expect(point.maxObstacleHeightFt == nil)
    }
  }

  @Test
  func tallestObstacleWinsAtSamePointIndex() async throws {
    let container = try makeModelContainer()
    let terrainService = TerrainService()
    let path = try #require(makeTestProcedurePath())

    // Insert two obstacles at the same location, different heights
    let midIndex = path.points.count / 2
    let midCoord = path.points[midIndex].coordinate
    let context = ModelContext(container)

    let short = Obstacle(
      heightMSL: .init(value: 200, unit: .feet),
      latitude: .init(value: midCoord.latitude, unit: .degrees),
      longitude: .init(value: midCoord.longitude, unit: .degrees)
    )
    let tall = Obstacle(
      heightMSL: .init(value: 800, unit: .feet),
      latitude: .init(value: midCoord.latitude + 0.0001, unit: .degrees),
      longitude: .init(value: midCoord.longitude, unit: .degrees)
    )
    context.insert(short)
    context.insert(tall)
    try context.save()

    let generator = ProcedureTerrainPathGenerator(
      modelContainer: container,
      terrainService: terrainService
    )
    let result = await generator.generate(from: path)

    let obstaclePoint = result.points.first { $0.maxObstacleHeightFt != nil }
    #expect(obstaclePoint != nil)
    #expect(
      obstaclePoint!.maxObstacleHeightFt!.isApproximatelyEqual(
        to: 800,
        absoluteTolerance: 1
      )
    )
  }

  // MARK: - Corridor Width

  @Test
  func corridorWidthIsStored() async throws {
    let container = try makeModelContainer()
    let terrainService = TerrainService()
    let path = try #require(makeTestProcedurePath())

    let generator = ProcedureTerrainPathGenerator(
      modelContainer: container,
      corridorWidthNM: 0.5,
      terrainService: terrainService
    )
    let result = await generator.generate(from: path)

    #expect(result.corridorWidthNM.isApproximatelyEqual(to: 0.5, absoluteTolerance: 0.001))
  }

  @Test
  func defaultCorridorWidth() async throws {
    let container = try makeModelContainer()
    let terrainService = TerrainService()
    let path = try #require(makeTestProcedurePath())

    let generator = ProcedureTerrainPathGenerator(
      modelContainer: container,
      terrainService: terrainService
    )
    let result = await generator.generate(from: path)

    #expect(result.corridorWidthNM.isApproximatelyEqual(to: 0.25, absoluteTolerance: 0.001))
  }
}

// MARK: - Obstacle.fetchDescriptor Tests

struct ObstacleFetchDescriptorTests {

  private func makeModelContainer() throws -> ModelContainer {
    let schema = Schema([
      Airport.self,
      Runway.self,
      NOTAM.self,
      Scenario.self,
      Cycle.self,
      Obstacle.self,
      Procedure.self,
      ProcedureSegment.self,
      Leg.self,
      Navaid.self
    ])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: [config])
  }

  @Test
  func fetchesObstaclesWithinBounds() throws {
    let container = try makeModelContainer()
    let context = ModelContext(container)

    let inside = Obstacle(
      heightMSL: .init(value: 100, unit: .feet),
      latitude: .init(value: 37.5, unit: .degrees),
      longitude: .init(value: -122.0, unit: .degrees)
    )
    let outside = Obstacle(
      heightMSL: .init(value: 200, unit: .feet),
      latitude: .init(value: 40.0, unit: .degrees),
      longitude: .init(value: -119.0, unit: .degrees)
    )
    context.insert(inside)
    context.insert(outside)
    try context.save()

    let descriptor = Obstacle.fetchDescriptor(
      minLat: 37.0,
      maxLat: 38.0,
      minLon: -123.0,
      maxLon: -121.0
    )
    let results = try context.fetch(descriptor)
    #expect(results.count == 1)
    #expect(
      results[0].heightMSL.converted(to: .feet).value.isApproximatelyEqual(
        to: 100,
        absoluteTolerance: 1
      )
    )
  }

  @Test
  func fetchReturnsEmptyWhenNoneInBounds() throws {
    let container = try makeModelContainer()
    let context = ModelContext(container)

    let obstacle = Obstacle(
      heightMSL: .init(value: 100, unit: .feet),
      latitude: .init(value: 37.5, unit: .degrees),
      longitude: .init(value: -122.0, unit: .degrees)
    )
    context.insert(obstacle)
    try context.save()

    let descriptor = Obstacle.fetchDescriptor(
      minLat: 50.0,
      maxLat: 51.0,
      minLon: -80.0,
      maxLon: -79.0
    )
    let results = try context.fetch(descriptor)
    #expect(results.isEmpty)
  }
}

// MARK: - ObstacleSurveyRegion Tests

struct ObstacleSurveyRegionTests {

  @Test
  func containsCONUSCoordinate() {
    let coord = CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0)  // San Jose, CA
    #expect(ObstacleSurveyRegion.contains(coordinate: coord))
  }

  @Test
  func containsAlaskaCoordinate() {
    let coord = CLLocationCoordinate2D(latitude: 61.2, longitude: -149.9)  // Anchorage
    #expect(ObstacleSurveyRegion.contains(coordinate: coord))
  }

  @Test
  func containsHawaiiCoordinate() {
    let coord = CLLocationCoordinate2D(latitude: 21.3, longitude: -157.8)  // Honolulu
    #expect(ObstacleSurveyRegion.contains(coordinate: coord))
  }

  @Test
  func doesNotContainEuropeCoordinate() {
    let coord = CLLocationCoordinate2D(latitude: 51.5, longitude: -0.1)  // London
    #expect(!ObstacleSurveyRegion.contains(coordinate: coord))
  }

  @Test
  func doesNotContainOpenOceanCoordinate() {
    let coord = CLLocationCoordinate2D(latitude: 30.0, longitude: -45.0)  // mid-Atlantic
    #expect(!ObstacleSurveyRegion.contains(coordinate: coord))
  }
}
