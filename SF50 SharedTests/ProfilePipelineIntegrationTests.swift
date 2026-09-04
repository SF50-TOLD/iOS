import CoreLocation
import Foundation
import RealModule
import SwiftData
import Testing

@testable import SF50_Shared

struct ProfilePipelineIntegrationTests {

  // MARK: - Shared Constants

  private let oakCoord = CLLocationCoordinate2D(latitude: 37.7213, longitude: -122.2208)
  private let magneticVariation = Measurement<UnitAngle>(value: -14, unit: .degrees)
  private let fieldElevationFt = 9.0

  private var climbProfile: ClimbProfile { Helper.createTestClimbProfile() }

  private func makeModelContainer() throws -> ModelContainer {
    let schema = Schema([
      Airport.self, Runway.self, NOTAM.self, Scenario.self, Cycle.self,
      Obstacle.self, Procedure.self, ProcedureSegment.self, Leg.self, Navaid.self
    ])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: [config])
  }

  // MARK: - Fixtures

  private func makeDepartureLegFixtures() -> [Leg] {
    [
      Helper.createTestLeg(
        identifier: "FIX1",
        latitude: 37.74,
        longitude: -122.25,
        legType: .initialFix,
        sequenceIndex: 0
      ),
      Helper.createTestLeg(
        identifier: "FIX2",
        latitude: 37.76,
        longitude: -122.30,
        legType: .trackToFix(course: .init(value: 292, unit: .degrees)),
        sequenceIndex: 1
      ),
      Helper.createTestLeg(
        identifier: "FIX3",
        latitude: 37.80,
        longitude: -122.35,
        legType: .trackToFix(course: .init(value: 330, unit: .degrees)),
        sequenceIndex: 2
      )
    ]
  }

  private func makeMissedApproachLegFixtures() -> [Leg] {
    [
      Helper.createTestLeg(
        identifier: "RW28R",
        latitude: 37.7213,
        longitude: -122.2208,
        legType: .initialFix,
        sequenceIndex: 0
      ),
      Helper.createTestLeg(
        identifier: "HA",
        latitude: 37.7213,
        longitude: -122.2208,
        altitudeRestriction: .atOrAbove(.init(value: 2000, unit: .feet)),
        legType: .headingToAltitude(heading: .init(value: 278, unit: .degrees)),
        sequenceIndex: 1
      ),
      Helper.createTestLeg(
        identifier: "GROVE",
        latitude: 37.76,
        longitude: -122.30,
        legType: .trackToFix(course: .init(value: 330, unit: .degrees)),
        sequenceIndex: 2
      )
    ]
  }

  private func insertObstacles(context: ModelContext) throws {
    let obstacle1 = Obstacle(
      heightMSL: .init(value: 300, unit: .feet),
      latitude: .init(value: 37.75, unit: .degrees),
      longitude: .init(value: -122.28, unit: .degrees)
    )
    let obstacle2 = Obstacle(
      heightMSL: .init(value: 450, unit: .feet),
      latitude: .init(value: 37.77, unit: .degrees),
      longitude: .init(value: -122.32, unit: .degrees)
    )
    context.insert(obstacle1)
    context.insert(obstacle2)
    try context.save()
  }

  // MARK: - Tests

  @Test
  func `departure pipeline end to end`() async throws {
    let container = try makeModelContainer()
    let terrainService = TerrainService()

    let pathGenerator = ProcedurePathGenerator(
      climbProfile: climbProfile,
      schedule: .init(segments: [.init(profile: .enroute(antiIce: false))]),
      magneticVariation: magneticVariation
    )
    let departurePath = try #require(
      pathGenerator.departurePath(
        from: makeDepartureLegFixtures(),
        takeoffPoint: oakCoord,
        takeoffPointAltitudeFt: fieldElevationFt
      )
    )

    let terrainGenerator = ProcedureTerrainPathGenerator(
      modelContainer: container,
      terrainService: terrainService
    )
    let result = await terrainGenerator.generate(from: departurePath)

    #expect(result.points.count == departurePath.points.count)
    for (i, terrainPoint) in result.points.enumerated() {
      let original = departurePath.points[i]
      #expect(
        terrainPoint.distanceNM.isApproximatelyEqual(
          to: original.distanceNM,
          absoluteTolerance: 0.001
        )
      )
      #expect(
        terrainPoint.aircraftAltitudeFt.isApproximatelyEqual(
          to: original.altitudeFt,
          absoluteTolerance: 0.001
        )
      )
    }
  }

  @Test
  func `go around pipeline end to end`() async throws {
    let container = try makeModelContainer()
    let terrainService = TerrainService()

    let pathGenerator = ProcedurePathGenerator(
      climbProfile: climbProfile,
      schedule: .init(segments: [
        .init(
          profile: .takeoff,
          upperBound: .time(.init(value: 2, unit: .minutes))
        ),
        .init(profile: .enrouteObstacle(antiIce: false))
      ]),
      magneticVariation: magneticVariation
    )
    let missedPath = try #require(
      pathGenerator.missedApproachPath(
        from: makeMissedApproachLegFixtures(),
        startCoordinate: oakCoord,
        startAltitudeFt: fieldElevationFt
      )
    )

    let terrainGenerator = ProcedureTerrainPathGenerator(
      modelContainer: container,
      terrainService: terrainService
    )
    let result = await terrainGenerator.generate(from: missedPath)

    #expect(!result.points.isEmpty)
    for (i, terrainPoint) in result.points.enumerated() {
      let original = missedPath.points[i]
      #expect(
        terrainPoint.distanceNM.isApproximatelyEqual(
          to: original.distanceNM,
          absoluteTolerance: 0.001
        )
      )
    }
  }

  @Test
  func `vectors mode pipeline`() async throws {
    let container = try makeModelContainer()
    let terrainService = TerrainService()

    let pathGenerator = ProcedurePathGenerator(
      climbProfile: climbProfile,
      schedule: .init(segments: [.init(profile: .enroute(antiIce: false))]),
      magneticVariation: magneticVariation
    )
    let headingPath = try #require(
      pathGenerator.headingPath(
        from: oakCoord,
        magneticDirection: .init(value: 280, unit: .degrees),
        isHeading: true,
        startAltitudeFt: fieldElevationFt,
        targetAltitudeFt: 3000
      )
    )

    let terrainGenerator = ProcedureTerrainPathGenerator(
      modelContainer: container,
      terrainService: terrainService
    )
    let result = await terrainGenerator.generate(from: headingPath)

    #expect(!result.points.isEmpty)
  }

  @Test
  func `obstacle detection`() async throws {
    let container = try makeModelContainer()
    let terrainService = TerrainService()

    let context = ModelContext(container)
    try insertObstacles(context: context)

    let pathGenerator = ProcedurePathGenerator(
      climbProfile: climbProfile,
      schedule: .init(segments: [.init(profile: .enroute(antiIce: false))]),
      magneticVariation: magneticVariation
    )
    let departurePath = try #require(
      pathGenerator.departurePath(
        from: makeDepartureLegFixtures(),
        takeoffPoint: oakCoord,
        takeoffPointAltitudeFt: fieldElevationFt
      )
    )

    let terrainGenerator = ProcedureTerrainPathGenerator(
      modelContainer: container,
      terrainService: terrainService
    )
    let result = await terrainGenerator.generate(from: departurePath)

    let hasObstacle = result.points.contains { $0.maxObstacleHeightFt != nil }
    #expect(hasObstacle)
  }

  @Test
  func `pipeline with no terrain data`() async throws {
    let container = try makeModelContainer()
    let terrainService = TerrainService()

    let pathGenerator = ProcedurePathGenerator(
      climbProfile: climbProfile,
      schedule: .init(segments: [.init(profile: .enroute(antiIce: false))]),
      magneticVariation: magneticVariation
    )
    let departurePath = try #require(
      pathGenerator.departurePath(
        from: makeDepartureLegFixtures(),
        takeoffPoint: oakCoord,
        takeoffPointAltitudeFt: fieldElevationFt
      )
    )

    let terrainGenerator = ProcedureTerrainPathGenerator(
      modelContainer: container,
      terrainService: terrainService
    )
    let result = await terrainGenerator.generate(from: departurePath)

    #expect(!result.terrainDataAvailable)
  }
}
