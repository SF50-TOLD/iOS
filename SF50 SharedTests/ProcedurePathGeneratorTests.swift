import CoreLocation
import Foundation
import RealModule
import Testing

@testable import SF50_Shared

struct ProcedurePathGeneratorTests {

  // MARK: - Shared Constants

  /// Standard takeoff point (San Jose area)
  private let takeoffPoint = CLLocationCoordinate2D(latitude: 37.3626, longitude: -121.9291)
  /// Standard variation: -14° (NORCAL, east declination stored as positive means magnetic = true - var,
  /// but the convention in GeoCalculations is positive = east, so true = magnetic + variation)
  private let magneticVariation = Measurement<UnitAngle>(value: -14, unit: .degrees)
  /// Standard start altitude
  private let takeoffAltitudeFt = 62.0
  /// Standard climb profile: 300 ft/NM constant
  private var climbProfile: ClimbProfile { Helper.createTestClimbProfile() }

  // MARK: - Departure Path Tests

  @Test
  func departurePathEmptyFixes() {
    let result = ProcedurePathGenerator(
      climbProfile: climbProfile,
      schedule: .init(segments: [.init(profile: .enroute(antiIce: false))]),
      magneticVariation: magneticVariation
    ).departurePath(
      from: [],
      takeoffPoint: takeoffPoint,
      takeoffPointAltitudeFt: takeoffAltitudeFt
    )
    #expect(result == nil)
  }

  @Test
  func departurePathSingleInitialFix() throws {
    let fix = Helper.createTestLeg(
      identifier: "ORCKA",
      latitude: 37.4,
      longitude: -122.0,
      legType: .initialFix,
      sequenceIndex: 0
    )
    let path = try #require(
      ProcedurePathGenerator(
        climbProfile: climbProfile,
        schedule: .init(segments: [.init(profile: .enroute(antiIce: false))]),
        magneticVariation: magneticVariation
      ).departurePath(
        from: [fix],
        takeoffPoint: takeoffPoint,
        takeoffPointAltitudeFt: takeoffAltitudeFt
      )
    )
    // Origin + intermediate steps + fix endpoint
    #expect(path.points.count >= 2)
    #expect(path.totalDistanceNM > 0)
  }

  @Test
  func departurePathPrependsOrigin() throws {
    let fix = Helper.createTestLeg(
      identifier: "ORCKA",
      latitude: 37.4,
      longitude: -122.0,
      legType: .initialFix,
      sequenceIndex: 0
    )
    let path = try #require(
      ProcedurePathGenerator(
        climbProfile: climbProfile,
        schedule: .init(segments: [.init(profile: .enroute(antiIce: false))]),
        magneticVariation: magneticVariation
      ).departurePath(
        from: [fix],
        takeoffPoint: takeoffPoint,
        takeoffPointAltitudeFt: takeoffAltitudeFt
      )
    )
    let origin = path.points[0]
    #expect(origin.distanceNM.isApproximatelyEqual(to: 0, absoluteTolerance: 0.001))
    #expect(origin.altitudeFt.isApproximatelyEqual(to: takeoffAltitudeFt, absoluteTolerance: 0.001))
    #expect(
      origin.coordinate.latitude.isApproximatelyEqual(
        to: takeoffPoint.latitude,
        absoluteTolerance: 0.0001
      )
    )
    #expect(
      origin.coordinate.longitude.isApproximatelyEqual(
        to: takeoffPoint.longitude,
        absoluteTolerance: 0.0001
      )
    )
  }

  @Test
  func departurePathMonotonicallyIncreasingDistance() throws {
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
      ),
      Helper.createTestLeg(
        identifier: "FIX3",
        latitude: 37.45,
        longitude: -122.05,
        legType: .directToFix,
        sequenceIndex: 2
      )
    ]
    let path = try #require(
      ProcedurePathGenerator(
        climbProfile: climbProfile,
        schedule: .init(segments: [.init(profile: .enroute(antiIce: false))]),
        magneticVariation: magneticVariation
      ).departurePath(
        from: fixes,
        takeoffPoint: takeoffPoint,
        takeoffPointAltitudeFt: takeoffAltitudeFt
      )
    )
    for i in 1..<path.points.count {
      #expect(path.points[i].distanceNM > path.points[i - 1].distanceNM)
    }
  }

  @Test
  func departurePathSortsFixesBySequenceIndex() throws {
    // Pass fixes out of order
    let fix0 = Helper.createTestLeg(
      identifier: "FIRST",
      latitude: 37.38,
      longitude: -121.95,
      legType: .initialFix,
      sequenceIndex: 0
    )
    let fix1 = Helper.createTestLeg(
      identifier: "SECOND",
      latitude: 37.40,
      longitude: -122.00,
      legType: .trackToFix(course: .init(value: 300, unit: .degrees)),
      sequenceIndex: 1
    )

    // Pass in reverse order
    let path = try #require(
      ProcedurePathGenerator(
        climbProfile: climbProfile,
        schedule: .init(segments: [.init(profile: .enroute(antiIce: false))]),
        magneticVariation: magneticVariation
      ).departurePath(
        from: [fix1, fix0],
        takeoffPoint: takeoffPoint,
        takeoffPointAltitudeFt: takeoffAltitudeFt
      )
    )
    // Should still produce valid monotonic path with many intermediate points
    #expect(path.points.count > 3)
    for i in 1..<path.points.count {
      #expect(path.points[i].distanceNM > path.points[i - 1].distanceNM)
    }
  }

  // MARK: - Fix-Terminated Legs (Straight Line)

  @Test
  func straightLineTrackToFix() throws {
    let fix = Helper.createTestLeg(
      identifier: "TF",
      latitude: 37.40,
      longitude: -122.00,
      legType: .trackToFix(course: .init(value: 300, unit: .degrees)),
      sequenceIndex: 0
    )
    let path = try #require(
      ProcedurePathGenerator(
        climbProfile: climbProfile,
        schedule: .init(segments: [.init(profile: .enroute(antiIce: false))]),
        magneticVariation: magneticVariation
      ).departurePath(
        from: [fix],
        takeoffPoint: takeoffPoint,
        takeoffPointAltitudeFt: takeoffAltitudeFt
      )
    )
    let lastPoint = path.points.last
    #expect(
      lastPoint?.coordinate.latitude.isApproximatelyEqual(to: 37.40, absoluteTolerance: 0.001)
        == true
    )
    #expect(
      lastPoint?.coordinate.longitude.isApproximatelyEqual(to: -122.00, absoluteTolerance: 0.001)
        == true
    )
  }

  @Test
  func straightLineCourseToFix() throws {
    let fix = Helper.createTestLeg(
      identifier: "CF",
      latitude: 37.40,
      longitude: -122.00,
      legType: .courseToFix(course: .init(value: 300, unit: .degrees)),
      sequenceIndex: 0
    )
    let path = try #require(
      ProcedurePathGenerator(
        climbProfile: climbProfile,
        schedule: .init(segments: [.init(profile: .enroute(antiIce: false))]),
        magneticVariation: magneticVariation
      ).departurePath(
        from: [fix],
        takeoffPoint: takeoffPoint,
        takeoffPointAltitudeFt: takeoffAltitudeFt
      )
    )
    let lastPoint = path.points.last
    #expect(
      lastPoint?.coordinate.latitude.isApproximatelyEqual(to: 37.40, absoluteTolerance: 0.001)
        == true
    )
    #expect(
      lastPoint?.coordinate.longitude.isApproximatelyEqual(to: -122.00, absoluteTolerance: 0.001)
        == true
    )
  }

  @Test
  func straightLineDirectToFix() throws {
    let fix = Helper.createTestLeg(
      identifier: "DF",
      latitude: 37.40,
      longitude: -122.00,
      legType: .directToFix,
      sequenceIndex: 0
    )
    let path = try #require(
      ProcedurePathGenerator(
        climbProfile: climbProfile,
        schedule: .init(segments: [.init(profile: .enroute(antiIce: false))]),
        magneticVariation: magneticVariation
      ).departurePath(
        from: [fix],
        takeoffPoint: takeoffPoint,
        takeoffPointAltitudeFt: takeoffAltitudeFt
      )
    )
    let lastPoint = path.points.last
    #expect(
      lastPoint?.coordinate.latitude.isApproximatelyEqual(to: 37.40, absoluteTolerance: 0.001)
        == true
    )
    #expect(
      lastPoint?.coordinate.longitude.isApproximatelyEqual(to: -122.00, absoluteTolerance: 0.001)
        == true
    )
  }

  @Test
  func straightLineDistanceAccuracy() throws {
    let fixCoord = CLLocationCoordinate2D(latitude: 37.40, longitude: -122.00)
    let fix = Helper.createTestLeg(
      identifier: "TF",
      latitude: fixCoord.latitude,
      longitude: fixCoord.longitude,
      legType: .trackToFix(course: .init(value: 300, unit: .degrees)),
      sequenceIndex: 0
    )
    let path = try #require(
      ProcedurePathGenerator(
        climbProfile: climbProfile,
        schedule: .init(segments: [.init(profile: .enroute(antiIce: false))]),
        magneticVariation: magneticVariation
      ).departurePath(
        from: [fix],
        takeoffPoint: takeoffPoint,
        takeoffPointAltitudeFt: takeoffAltitudeFt
      )
    )
    let expectedNM = GeoCalculations.distanceNM(from: takeoffPoint, to: fixCoord)
    // Last point is the fix
    let lastPoint = path.points.last!
    #expect(lastPoint.distanceNM.isApproximatelyEqual(to: expectedNM, relativeTolerance: 0.02))
  }

  // MARK: - *ToAltitude Legs

  @Test
  func fixToAltitudeProjection() throws {
    let fix = Helper.createTestLeg(
      identifier: "IF",
      latitude: 37.38,
      longitude: -121.95,
      legType: .initialFix,
      sequenceIndex: 0
    )
    let faFix = Helper.createTestLeg(
      identifier: "FA",
      latitude: 37.38,
      longitude: -121.95,
      altitudeRestriction: .at(.init(value: 5000, unit: .feet)),
      legType: .fixToAltitude(course: .init(value: 360, unit: .degrees)),
      sequenceIndex: 1
    )
    let path = try #require(
      ProcedurePathGenerator(
        climbProfile: climbProfile,
        schedule: .init(segments: [.init(profile: .enroute(antiIce: false))]),
        magneticVariation: magneticVariation
      ).departurePath(
        from: [fix, faFix],
        takeoffPoint: takeoffPoint,
        takeoffPointAltitudeFt: takeoffAltitudeFt
      )
    )
    // Should project along true course (360 + (-14) = 346°)
    // Distance should approximate climbProfile.distance(from: currentAlt, to: 5000)
    #expect(path.points.count >= 3)  // origin + initialFix steps + altitude steps
    let lastPoint = path.points.last
    #expect(lastPoint?.distanceNM ?? 0 > 0)
    // Final altitude should be at the target
    #expect(lastPoint?.altitudeFt.isApproximatelyEqual(to: 5000, absoluteTolerance: 1) == true)
  }

  @Test
  func courseToAltitudeProjection() throws {
    let fix = Helper.createTestLeg(
      identifier: "IF",
      latitude: 37.38,
      longitude: -121.95,
      legType: .initialFix,
      sequenceIndex: 0
    )
    let caFix = Helper.createTestLeg(
      identifier: "CA",
      latitude: 37.38,
      longitude: -121.95,
      altitudeRestriction: .at(.init(value: 5000, unit: .feet)),
      legType: .courseToAltitude(course: .init(value: 360, unit: .degrees)),
      sequenceIndex: 1
    )
    let path = try #require(
      ProcedurePathGenerator(
        climbProfile: climbProfile,
        schedule: .init(segments: [.init(profile: .enroute(antiIce: false))]),
        magneticVariation: magneticVariation
      ).departurePath(
        from: [fix, caFix],
        takeoffPoint: takeoffPoint,
        takeoffPointAltitudeFt: takeoffAltitudeFt
      )
    )
    #expect(path.points.count >= 3)
    #expect(
      path.points.last?.altitudeFt.isApproximatelyEqual(to: 5000, absoluteTolerance: 1) == true
    )
  }

  @Test
  func headingToAltitudeProjection() throws {
    let fix = Helper.createTestLeg(
      identifier: "IF",
      latitude: 37.38,
      longitude: -121.95,
      legType: .initialFix,
      sequenceIndex: 0
    )
    let haFix = Helper.createTestLeg(
      identifier: "HA",
      latitude: 37.38,
      longitude: -121.95,
      altitudeRestriction: .at(.init(value: 5000, unit: .feet)),
      legType: .headingToAltitude(heading: .init(value: 360, unit: .degrees)),
      sequenceIndex: 1
    )
    let path = try #require(
      ProcedurePathGenerator(
        climbProfile: climbProfile,
        schedule: .init(segments: [.init(profile: .enroute(antiIce: false))]),
        magneticVariation: magneticVariation
      ).departurePath(
        from: [fix, haFix],
        takeoffPoint: takeoffPoint,
        takeoffPointAltitudeFt: takeoffAltitudeFt
      )
    )
    #expect(path.points.count >= 3)
    #expect(
      path.points.last?.altitudeFt.isApproximatelyEqual(to: 5000, absoluteTolerance: 1) == true
    )
  }

  @Test
  func toAltitudeAtOrAboveRestriction() throws {
    let fix = Helper.createTestLeg(
      identifier: "IF",
      latitude: 37.38,
      longitude: -121.95,
      legType: .initialFix,
      sequenceIndex: 0
    )
    let faFix = Helper.createTestLeg(
      identifier: "FA",
      latitude: 37.38,
      longitude: -121.95,
      altitudeRestriction: .atOrAbove(.init(value: 4000, unit: .feet)),
      legType: .fixToAltitude(course: .init(value: 360, unit: .degrees)),
      sequenceIndex: 1
    )
    let path = try #require(
      ProcedurePathGenerator(
        climbProfile: climbProfile,
        schedule: .init(segments: [.init(profile: .enroute(antiIce: false))]),
        magneticVariation: magneticVariation
      ).departurePath(
        from: [fix, faFix],
        takeoffPoint: takeoffPoint,
        takeoffPointAltitudeFt: takeoffAltitudeFt
      )
    )
    #expect(path.points.count >= 3)
    #expect(
      path.points.last?.altitudeFt.isApproximatelyEqual(to: 4000, absoluteTolerance: 1) == true
    )
  }

  @Test
  func toAltitudeBetweenRestriction() throws {
    let fix = Helper.createTestLeg(
      identifier: "IF",
      latitude: 37.38,
      longitude: -121.95,
      legType: .initialFix,
      sequenceIndex: 0
    )
    let faFix = Helper.createTestLeg(
      identifier: "FA",
      latitude: 37.38,
      longitude: -121.95,
      altitudeRestriction: .between(
        min: .init(value: 3000, unit: .feet),
        max: .init(value: 5000, unit: .feet)
      ),
      legType: .fixToAltitude(course: .init(value: 360, unit: .degrees)),
      sequenceIndex: 1
    )
    let path = try #require(
      ProcedurePathGenerator(
        climbProfile: climbProfile,
        schedule: .init(segments: [.init(profile: .enroute(antiIce: false))]),
        magneticVariation: magneticVariation
      ).departurePath(
        from: [fix, faFix],
        takeoffPoint: takeoffPoint,
        takeoffPointAltitudeFt: takeoffAltitudeFt
      )
    )
    #expect(path.points.count >= 3)
    // Between restriction uses min as climb target
    #expect(
      path.points.last?.altitudeFt.isApproximatelyEqual(to: 3000, absoluteTolerance: 1) == true
    )
  }

  @Test
  func toAltitudeNoRestriction() {
    let fix = Helper.createTestLeg(
      identifier: "IF",
      latitude: 37.38,
      longitude: -121.95,
      legType: .initialFix,
      sequenceIndex: 0
    )
    // No altitude restriction → can't determine projection
    let faFix = Helper.createTestLeg(
      identifier: "FA",
      latitude: 37.38,
      longitude: -121.95,
      altitudeRestriction: nil,
      legType: .fixToAltitude(course: .init(value: 360, unit: .degrees)),
      sequenceIndex: 1
    )
    let result = ProcedurePathGenerator(
      climbProfile: climbProfile,
      schedule: .init(segments: [.init(profile: .enroute(antiIce: false))]),
      magneticVariation: magneticVariation
    ).departurePath(
      from: [fix, faFix],
      takeoffPoint: takeoffPoint,
      takeoffPointAltitudeFt: takeoffAltitudeFt
    )
    #expect(result == nil)
  }

  @Test
  func toAltitudeMagneticToTrueConversion() throws {
    // Two fixes due north: magnetic 360° with variation -14° should give true 346°
    // The endpoint should be offset west (bearing < 360) from due north
    let startCoord = CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0)
    let fix = Helper.createTestLeg(
      identifier: "IF",
      latitude: startCoord.latitude,
      longitude: startCoord.longitude,
      legType: .initialFix,
      sequenceIndex: 0
    )
    let faFix = Helper.createTestLeg(
      identifier: "FA",
      latitude: startCoord.latitude,
      longitude: startCoord.longitude,
      altitudeRestriction: .at(.init(value: 5000, unit: .feet)),
      legType: .fixToAltitude(course: .init(value: 360, unit: .degrees)),
      sequenceIndex: 1
    )
    let path = try #require(
      ProcedurePathGenerator(
        climbProfile: climbProfile,
        schedule: .init(segments: [.init(profile: .enroute(antiIce: false))]),
        magneticVariation: magneticVariation
      ).departurePath(
        from: [fix, faFix],
        takeoffPoint: startCoord,
        takeoffPointAltitudeFt: 0
      )
    )
    // The projected endpoint should be west of due north (negative variation shifts bearing west)
    let endpoint = path.points.last
    #expect(endpoint != nil)
    // True course 346° is NNW, so endpoint longitude should be more negative (further west)
    #expect((endpoint?.coordinate.longitude ?? 0) < startCoord.longitude)
  }

  // MARK: - Altitude Capping (atOrBelow)

  @Test
  func atOrBelowCapsAltitude() throws {
    // Place fix1 far enough that uncapped climb would exceed 3000 ft
    // At 300 ft/NM from 62 ft, need ~10 NM to reach 3062 ft
    // Place fix1 ~15 NM away so uncapped altitude would be ~4562 ft
    // atOrBelow(3000) should level off at 3000 during the climb, not just cap the endpoint
    // Then fixToAltitude(6000) should climb from 3000 (capped) -> 6000 = 3000 ft / 300 = 10 NM
    let profile = Helper.createTestClimbProfile(gradientFtPerNM: 300)

    // ~15 NM north of takeoff (~0.25° latitude)
    let fix1 = Helper.createTestLeg(
      identifier: "FIX1",
      latitude: 37.6126,
      longitude: -121.9291,
      altitudeRestriction: .atOrBelow(.init(value: 3000, unit: .feet)),
      legType: .initialFix,
      sequenceIndex: 0
    )
    let fix2 = Helper.createTestLeg(
      identifier: "FIX2",
      latitude: 37.6126,
      longitude: -121.9291,
      altitudeRestriction: .at(.init(value: 6000, unit: .feet)),
      legType: .fixToAltitude(course: .init(value: 360, unit: .degrees)),
      sequenceIndex: 1
    )

    let path = try #require(
      ProcedurePathGenerator(
        climbProfile: profile,
        schedule: .init(segments: [.init(profile: .enroute(antiIce: false))]),
        magneticVariation: magneticVariation
      ).departurePath(
        from: [fix1, fix2],
        takeoffPoint: takeoffPoint,
        takeoffPointAltitudeFt: takeoffAltitudeFt
      )
    )

    // The fix2 endpoint altitude should be 6000
    let lastPoint = path.points.last!
    #expect(lastPoint.altitudeFt.isApproximatelyEqual(to: 6000, absoluteTolerance: 1))

    // Total path distance should be approximately 15 + 10 = 25 NM
    #expect(lastPoint.distanceNM.isApproximatelyEqual(to: 25, absoluteTolerance: 1.5))

    // Verify all points in the first segment (including the termination fix)
    // respect the atOrBelow cap exactly.
    let fix1Index = path.points.firstIndex { $0.fixName == "FIX1" }!
    let firstSegmentPoints = path.points[0...fix1Index]
    let maxAltInFirstSegment = firstSegmentPoints.map(\.altitudeFt).max()!
    #expect(
      maxAltInFirstSegment <= 3000,
      "All points including the termination fix should respect the atOrBelow cap"
    )
  }

  // MARK: - Hold Patterns

  @Test
  func holdAsTerminalLeg() throws {
    let fix = Helper.createTestLeg(
      identifier: "HOLD",
      latitude: 37.40,
      longitude: -122.00,
      legType: .holdToFix(
        course: .init(value: 360, unit: .degrees),
        turnDirection: .right
      ),
      sequenceIndex: 0
    )
    let path = try #require(
      ProcedurePathGenerator(
        climbProfile: climbProfile,
        schedule: .init(segments: [.init(profile: .enroute(antiIce: false))]),
        magneticVariation: magneticVariation
      ).departurePath(
        from: [fix],
        takeoffPoint: takeoffPoint,
        takeoffPointAltitudeFt: takeoffAltitudeFt
      )
    )
    let lastPoint = path.points.last
    #expect(
      lastPoint?.coordinate.latitude.isApproximatelyEqual(to: 37.40, absoluteTolerance: 0.001)
        == true
    )
    #expect(
      lastPoint?.coordinate.longitude.isApproximatelyEqual(to: -122.00, absoluteTolerance: 0.001)
        == true
    )
  }

  @Test
  func holdAsNonTerminalLeg() {
    let holdFix = Helper.createTestLeg(
      identifier: "HOLD",
      latitude: 37.40,
      longitude: -122.00,
      legType: .holdToFix(
        course: .init(value: 360, unit: .degrees),
        turnDirection: .right
      ),
      sequenceIndex: 0
    )
    let nextFix = Helper.createTestLeg(
      identifier: "NEXT",
      latitude: 37.45,
      longitude: -122.05,
      legType: .directToFix,
      sequenceIndex: 1
    )
    let result = ProcedurePathGenerator(
      climbProfile: climbProfile,
      schedule: .init(segments: [.init(profile: .enroute(antiIce: false))]),
      magneticVariation: magneticVariation
    ).departurePath(
      from: [holdFix, nextFix],
      takeoffPoint: takeoffPoint,
      takeoffPointAltitudeFt: takeoffAltitudeFt
    )
    #expect(result == nil)
  }

  @Test
  func holdToAltitudeTerminal() throws {
    let fix = Helper.createTestLeg(
      identifier: "HOLD",
      latitude: 37.40,
      longitude: -122.00,
      legType: .holdToAltitude(
        course: .init(value: 360, unit: .degrees),
        turnDirection: .left
      ),
      sequenceIndex: 0
    )
    let path = try #require(
      ProcedurePathGenerator(
        climbProfile: climbProfile,
        schedule: .init(segments: [.init(profile: .enroute(antiIce: false))]),
        magneticVariation: magneticVariation
      ).departurePath(
        from: [fix],
        takeoffPoint: takeoffPoint,
        takeoffPointAltitudeFt: takeoffAltitudeFt
      )
    )
    let lastPoint = path.points.last
    #expect(
      lastPoint?.coordinate.latitude.isApproximatelyEqual(to: 37.40, absoluteTolerance: 0.001)
        == true
    )
  }

  @Test
  func holdManualTerminal() throws {
    let fix = Helper.createTestLeg(
      identifier: "HOLD",
      latitude: 37.40,
      longitude: -122.00,
      legType: .holdManual(
        course: .init(value: 360, unit: .degrees),
        turnDirection: .either
      ),
      sequenceIndex: 0
    )
    let path = try #require(
      ProcedurePathGenerator(
        climbProfile: climbProfile,
        schedule: .init(segments: [.init(profile: .enroute(antiIce: false))]),
        magneticVariation: magneticVariation
      ).departurePath(
        from: [fix],
        takeoffPoint: takeoffPoint,
        takeoffPointAltitudeFt: takeoffAltitudeFt
      )
    )
    let lastPoint = path.points.last
    #expect(
      lastPoint?.coordinate.latitude.isApproximatelyEqual(to: 37.40, absoluteTolerance: 0.001)
        == true
    )
  }

  // MARK: - Procedure Turn

  @Test
  func procedureTurnTerminal() throws {
    let fix = Helper.createTestLeg(
      identifier: "PT",
      latitude: 37.40,
      longitude: -122.00,
      legType: .procedureTurn(
        course: .init(value: 360, unit: .degrees),
        turnDirection: .right
      ),
      sequenceIndex: 0
    )
    let path = try #require(
      ProcedurePathGenerator(
        climbProfile: climbProfile,
        schedule: .init(segments: [.init(profile: .enroute(antiIce: false))]),
        magneticVariation: magneticVariation
      ).departurePath(
        from: [fix],
        takeoffPoint: takeoffPoint,
        takeoffPointAltitudeFt: takeoffAltitudeFt
      )
    )
    let lastPoint = path.points.last
    #expect(
      lastPoint?.coordinate.latitude.isApproximatelyEqual(to: 37.40, absoluteTolerance: 0.001)
        == true
    )
  }

  @Test
  func procedureTurnNonTerminal() {
    let ptFix = Helper.createTestLeg(
      identifier: "PT",
      latitude: 37.40,
      longitude: -122.00,
      legType: .procedureTurn(
        course: .init(value: 360, unit: .degrees),
        turnDirection: .right
      ),
      sequenceIndex: 0
    )
    let nextFix = Helper.createTestLeg(
      identifier: "NEXT",
      latitude: 37.45,
      longitude: -122.05,
      legType: .directToFix,
      sequenceIndex: 1
    )
    let result = ProcedurePathGenerator(
      climbProfile: climbProfile,
      schedule: .init(segments: [.init(profile: .enroute(antiIce: false))]),
      magneticVariation: magneticVariation
    ).departurePath(
      from: [ptFix, nextFix],
      takeoffPoint: takeoffPoint,
      takeoffPointAltitudeFt: takeoffAltitudeFt
    )
    #expect(result == nil)
  }

  // MARK: - Non-Plottable Legs (Return Nil)

  @Test
  func courseToDMEReturnsNil() {
    let fix = Helper.createTestLeg(
      legType: .courseToDME(course: .init(value: 360, unit: .degrees)),
      sequenceIndex: 0
    )
    let result = ProcedurePathGenerator(
      climbProfile: climbProfile,
      schedule: .init(segments: [.init(profile: .enroute(antiIce: false))]),
      magneticVariation: magneticVariation
    ).departurePath(
      from: [fix],
      takeoffPoint: takeoffPoint,
      takeoffPointAltitudeFt: takeoffAltitudeFt
    )
    #expect(result == nil)
  }

  @Test
  func courseToInterceptWithNextLeg() throws {
    // CI flying course 284° mag (true 270° west), intercept CF course 14° mag (true 0° north)
    // through fix at 37.5, -122.0. Aircraft starts east of the N-S course line and flies west.
    let fix = CLLocationCoordinate2D(latitude: 37.5, longitude: -122.0)
    let startCoord = CLLocationCoordinate2D(latitude: 37.4, longitude: -121.9)
    let ciLeg = Helper.createTestLeg(
      identifier: nil,
      latitude: nil,
      longitude: nil,
      legType: .courseToIntercept(course: .init(value: 284, unit: .degrees)),
      sequenceIndex: 0
    )
    let cfLeg = Helper.createTestLeg(
      identifier: "FIX",
      latitude: fix.latitude,
      longitude: fix.longitude,
      altitudeRestriction: .atOrAbove(.init(value: 10000, unit: .feet)),
      legType: .courseToFix(course: .init(value: 14, unit: .degrees)),
      sequenceIndex: 1
    )
    let path = try #require(
      ProcedurePathGenerator(
        climbProfile: climbProfile,
        schedule: .init(segments: [.init(profile: .enroute(antiIce: false))]),
        magneticVariation: magneticVariation
      ).departurePath(
        from: [ciLeg, cfLeg],
        takeoffPoint: startCoord,
        takeoffPointAltitudeFt: takeoffAltitudeFt
      )
    )
    // Path should have points and end at the fix
    #expect(path.points.count >= 3)
    let lastPoint = path.points.last!
    #expect(
      lastPoint.coordinate.latitude.isApproximatelyEqual(
        to: fix.latitude,
        absoluteTolerance: 0.001
      )
    )
    #expect(
      lastPoint.coordinate.longitude.isApproximatelyEqual(
        to: fix.longitude,
        absoluteTolerance: 0.001
      )
    )
  }

  @Test
  func courseToInterceptNoNextLegReturnsNil() {
    let fix = Helper.createTestLeg(
      legType: .courseToIntercept(course: .init(value: 360, unit: .degrees)),
      sequenceIndex: 0
    )
    let result = ProcedurePathGenerator(
      climbProfile: climbProfile,
      schedule: .init(segments: [.init(profile: .enroute(antiIce: false))]),
      magneticVariation: magneticVariation
    ).departurePath(
      from: [fix],
      takeoffPoint: takeoffPoint,
      takeoffPointAltitudeFt: takeoffAltitudeFt
    )
    #expect(result == nil)
  }

  @Test
  func courseToRadialTerminatesAtRadial() throws {
    // CR flying course 284° mag (true 270° west) until intercepting the 014° magnetic
    // radial (true 000° north) from a VOR at 37.5, -122.0.
    // Aircraft starts east of the VOR and flies west to cross the north radial.
    let vorCoord = CLLocationCoordinate2D(latitude: 37.5, longitude: -122.0)
    let startCoord = CLLocationCoordinate2D(latitude: 37.4, longitude: -121.9)

    let vor = Helper.createTestNavaid(
      identifier: "TST",
      latitude: vorCoord.latitude,
      longitude: vorCoord.longitude
    )
    let crLeg = Helper.createTestLeg(
      identifier: nil,
      latitude: nil,
      longitude: nil,
      legType: .courseToRadial(course: .init(value: 284, unit: .degrees)),
      sequenceIndex: 0,
      navaid: vor,
      theta: .init(value: 14, unit: .degrees)
    )

    let path = try #require(
      ProcedurePathGenerator(
        climbProfile: climbProfile,
        schedule: .init(segments: [.init(profile: .enroute(antiIce: false))]),
        magneticVariation: magneticVariation
      ).departurePath(
        from: [crLeg],
        takeoffPoint: startCoord,
        takeoffPointAltitudeFt: takeoffAltitudeFt
      )
    )

    // The path should cross the north radial from the VOR (longitude ≈ -122.0)
    #expect(path.points.count >= 3)
    let lastPoint = path.points.last!
    #expect(
      lastPoint.coordinate.longitude.isApproximatelyEqual(
        to: vorCoord.longitude,
        absoluteTolerance: 0.01
      )
    )
  }

  @Test
  func courseToRadialMissingNavaidReturnsNil() {
    let crLeg = Helper.createTestLeg(
      identifier: nil,
      latitude: nil,
      longitude: nil,
      legType: .courseToRadial(course: .init(value: 284, unit: .degrees)),
      sequenceIndex: 0,
      theta: .init(value: 14, unit: .degrees)
    )
    let result = ProcedurePathGenerator(
      climbProfile: climbProfile,
      schedule: .init(segments: [.init(profile: .enroute(antiIce: false))]),
      magneticVariation: magneticVariation
    ).departurePath(
      from: [crLeg],
      takeoffPoint: takeoffPoint,
      takeoffPointAltitudeFt: takeoffAltitudeFt
    )
    #expect(result == nil)
  }

  @Test
  func courseToRadialMissingThetaReturnsNil() {
    let vor = Helper.createTestNavaid()
    let crLeg = Helper.createTestLeg(
      identifier: nil,
      latitude: nil,
      longitude: nil,
      legType: .courseToRadial(course: .init(value: 284, unit: .degrees)),
      sequenceIndex: 0,
      navaid: vor
    )
    let result = ProcedurePathGenerator(
      climbProfile: climbProfile,
      schedule: .init(segments: [.init(profile: .enroute(antiIce: false))]),
      magneticVariation: magneticVariation
    ).departurePath(
      from: [crLeg],
      takeoffPoint: takeoffPoint,
      takeoffPointAltitudeFt: takeoffAltitudeFt
    )
    #expect(result == nil)
  }

  @Test
  func headingToDMEReturnsNil() {
    let fix = Helper.createTestLeg(
      legType: .headingToDME(heading: .init(value: 360, unit: .degrees)),
      sequenceIndex: 0
    )
    let result = ProcedurePathGenerator(
      climbProfile: climbProfile,
      schedule: .init(segments: [.init(profile: .enroute(antiIce: false))]),
      magneticVariation: magneticVariation
    ).departurePath(
      from: [fix],
      takeoffPoint: takeoffPoint,
      takeoffPointAltitudeFt: takeoffAltitudeFt
    )
    #expect(result == nil)
  }

  @Test
  func headingToInterceptWithNextLeg() throws {
    // LINDZ1 pattern: VA 343° to 9100', VI 273° to intercept, CF 303° to LINDZ
    // After VA (true 329° NNW), aircraft is north of course line.
    // VI (true 259° WSW) crosses the 289° true course line through LINDZ.
    let lindz = CLLocationCoordinate2D(latitude: 39.0, longitude: -107.0)
    let startCoord = CLLocationCoordinate2D(latitude: 39.0, longitude: -106.8)

    let vaLeg = Helper.createTestLeg(
      identifier: nil,
      latitude: nil,
      longitude: nil,
      altitudeRestriction: .atOrAbove(.init(value: 9100, unit: .feet)),
      legType: .headingToAltitude(heading: .init(value: 343, unit: .degrees)),
      sequenceIndex: 0
    )
    let viLeg = Helper.createTestLeg(
      identifier: nil,
      latitude: nil,
      longitude: nil,
      legType: .headingToIntercept(heading: .init(value: 273, unit: .degrees)),
      sequenceIndex: 1
    )
    let cfLeg = Helper.createTestLeg(
      identifier: "LINDZ",
      latitude: lindz.latitude,
      longitude: lindz.longitude,
      altitudeRestriction: .atOrAbove(.init(value: 15000, unit: .feet)),
      legType: .courseToFix(course: .init(value: 303, unit: .degrees)),
      sequenceIndex: 2
    )

    let path = try #require(
      ProcedurePathGenerator(
        climbProfile: climbProfile,
        schedule: .init(segments: [.init(profile: .enroute(antiIce: false))]),
        magneticVariation: magneticVariation
      ).departurePath(
        from: [vaLeg, viLeg, cfLeg],
        takeoffPoint: startCoord,
        takeoffPointAltitudeFt: 7820
      )
    )

    // Path should include all three legs and end at LINDZ
    #expect(path.points.count > 5)
    let lastPoint = path.points.last!
    #expect(
      lastPoint.coordinate.latitude.isApproximatelyEqual(
        to: lindz.latitude,
        absoluteTolerance: 0.001
      )
    )
    #expect(
      lastPoint.coordinate.longitude.isApproximatelyEqual(
        to: lindz.longitude,
        absoluteTolerance: 0.001
      )
    )
  }

  @Test
  func headingToInterceptNoNextLegReturnsNil() {
    let fix = Helper.createTestLeg(
      legType: .headingToIntercept(heading: .init(value: 360, unit: .degrees)),
      sequenceIndex: 0
    )
    let result = ProcedurePathGenerator(
      climbProfile: climbProfile,
      schedule: .init(segments: [.init(profile: .enroute(antiIce: false))]),
      magneticVariation: magneticVariation
    ).departurePath(
      from: [fix],
      takeoffPoint: takeoffPoint,
      takeoffPointAltitudeFt: takeoffAltitudeFt
    )
    #expect(result == nil)
  }

  @Test
  func headingToInterceptTerminatesOnCourseLine() throws {
    // VI heading 284° mag (true 270° west) intercepting CF course 14° mag (true 0° north)
    // through a fix due north. Aircraft starts east of the N-S course line and flies west.
    let interceptPoint = CLLocationCoordinate2D(latitude: 37.5, longitude: -122.0)
    let startCoord = CLLocationCoordinate2D(latitude: 37.4, longitude: -121.9)

    let viLeg = Helper.createTestLeg(
      identifier: nil,
      latitude: nil,
      longitude: nil,
      legType: .headingToIntercept(heading: .init(value: 284, unit: .degrees)),
      sequenceIndex: 0
    )
    let cfLeg = Helper.createTestLeg(
      identifier: "FIX",
      latitude: interceptPoint.latitude,
      longitude: interceptPoint.longitude,
      altitudeRestriction: .atOrAbove(.init(value: 10000, unit: .feet)),
      legType: .courseToFix(course: .init(value: 14, unit: .degrees)),
      sequenceIndex: 1
    )

    let path = try #require(
      ProcedurePathGenerator(
        climbProfile: climbProfile,
        schedule: .init(segments: [.init(profile: .enroute(antiIce: false))]),
        magneticVariation: magneticVariation
      ).departurePath(
        from: [viLeg, cfLeg],
        takeoffPoint: startCoord,
        takeoffPointAltitudeFt: takeoffAltitudeFt
      )
    )

    // The VI leg terminates on the course line (true 0° through -122.0 longitude),
    // then the CF leg continues to the fix.
    #expect(path.points.count > 3)

    // The last point should be at the fix
    let lastPoint = path.points.last!
    #expect(
      lastPoint.coordinate.latitude.isApproximatelyEqual(
        to: interceptPoint.latitude,
        absoluteTolerance: 0.001
      )
    )
    #expect(
      lastPoint.coordinate.longitude.isApproximatelyEqual(
        to: interceptPoint.longitude,
        absoluteTolerance: 0.001
      )
    )
  }

  @Test
  func headingToRadialTerminatesAtRadial() throws {
    // VR heading 284° mag (true 270° west) until intercepting the 014° magnetic
    // radial (true 000° north) from a VOR at 37.5, -122.0.
    let vorCoord = CLLocationCoordinate2D(latitude: 37.5, longitude: -122.0)
    let startCoord = CLLocationCoordinate2D(latitude: 37.4, longitude: -121.9)

    let vor = Helper.createTestNavaid(
      identifier: "TST",
      latitude: vorCoord.latitude,
      longitude: vorCoord.longitude
    )
    let vrLeg = Helper.createTestLeg(
      identifier: nil,
      latitude: nil,
      longitude: nil,
      legType: .headingToRadial(heading: .init(value: 284, unit: .degrees)),
      sequenceIndex: 0,
      navaid: vor,
      theta: .init(value: 14, unit: .degrees)
    )

    let path = try #require(
      ProcedurePathGenerator(
        climbProfile: climbProfile,
        schedule: .init(segments: [.init(profile: .enroute(antiIce: false))]),
        magneticVariation: magneticVariation
      ).departurePath(
        from: [vrLeg],
        takeoffPoint: startCoord,
        takeoffPointAltitudeFt: takeoffAltitudeFt
      )
    )

    // The path should cross the north radial from the VOR (longitude ≈ -122.0)
    #expect(path.points.count >= 3)
    let lastPoint = path.points.last!
    #expect(
      lastPoint.coordinate.longitude.isApproximatelyEqual(
        to: vorCoord.longitude,
        absoluteTolerance: 0.01
      )
    )
  }

  @Test
  func trackFromFixDistanceReturnsNil() {
    let fix = Helper.createTestLeg(
      legType: .trackFromFixDistance(course: .init(value: 360, unit: .degrees)),
      sequenceIndex: 0
    )
    let result = ProcedurePathGenerator(
      climbProfile: climbProfile,
      schedule: .init(segments: [.init(profile: .enroute(antiIce: false))]),
      magneticVariation: magneticVariation
    ).departurePath(
      from: [fix],
      takeoffPoint: takeoffPoint,
      takeoffPointAltitudeFt: takeoffAltitudeFt
    )
    #expect(result == nil)
  }

  @Test
  func trackFromFixDMEReturnsNil() {
    let fix = Helper.createTestLeg(
      legType: .trackFromFixDME(course: .init(value: 360, unit: .degrees)),
      sequenceIndex: 0
    )
    let result = ProcedurePathGenerator(
      climbProfile: climbProfile,
      schedule: .init(segments: [.init(profile: .enroute(antiIce: false))]),
      magneticVariation: magneticVariation
    ).departurePath(
      from: [fix],
      takeoffPoint: takeoffPoint,
      takeoffPointAltitudeFt: takeoffAltitudeFt
    )
    #expect(result == nil)
  }

  // MARK: - Arc Legs

  @Test
  func radiusToFixGeneratesArcPoints() throws {
    let initialFix = Helper.createTestLeg(
      identifier: "START",
      latitude: 37.40,
      longitude: -122.00,
      legType: .initialFix,
      sequenceIndex: 0
    )
    // Place the end fix at a location that makes sense for an arc
    let arcFix = Helper.createTestLeg(
      identifier: "ARC",
      latitude: 37.42,
      longitude: -121.98,
      legType: .radiusToFix(
        arcRadius: .init(value: 5, unit: .nauticalMiles),
        course: .init(value: 180, unit: .degrees)
      ),
      sequenceIndex: 1
    )
    let path = try #require(
      ProcedurePathGenerator(
        climbProfile: climbProfile,
        schedule: .init(segments: [.init(profile: .enroute(antiIce: false))]),
        magneticVariation: magneticVariation
      ).departurePath(
        from: [initialFix, arcFix],
        takeoffPoint: takeoffPoint,
        takeoffPointAltitudeFt: takeoffAltitudeFt
      )
    )
    // Should have origin + initialFix steps + arc intermediate points + arc endpoint
    #expect(path.points.count > 3)
  }

  @Test
  func radiusToFixPointsNearArcRadius() throws {
    let startCoord = CLLocationCoordinate2D(latitude: 37.40, longitude: -122.00)
    let initialFix = Helper.createTestLeg(
      identifier: "START",
      latitude: startCoord.latitude,
      longitude: startCoord.longitude,
      legType: .initialFix,
      sequenceIndex: 0
    )
    let arcRadiusNM = 5.0
    let courseDeg = 180.0  // magnetic bearing from center to start of arc
    let arcFix = Helper.createTestLeg(
      identifier: "ARC",
      latitude: 37.42,
      longitude: -121.96,
      legType: .radiusToFix(
        arcRadius: .init(value: arcRadiusNM, unit: .nauticalMiles),
        course: .init(value: courseDeg, unit: .degrees)
      ),
      sequenceIndex: 1
    )
    let path = try #require(
      ProcedurePathGenerator(
        climbProfile: climbProfile,
        schedule: .init(segments: [.init(profile: .enroute(antiIce: false))]),
        magneticVariation: magneticVariation
      ).departurePath(
        from: [initialFix, arcFix],
        takeoffPoint: takeoffPoint,
        takeoffPointAltitudeFt: takeoffAltitudeFt
      )
    )

    // Compute the arc center: it's at arcRadius from startCoord along reciprocal of true course
    let trueCourse = courseDeg + magneticVariation.converted(to: .degrees).value
    let reciprocal = (trueCourse + 180).truncatingRemainder(dividingBy: 360)
    let center = GeoCalculations.destination(
      from: startCoord,
      distance: .init(value: arcRadiusNM, unit: .nauticalMiles),
      bearing: .init(value: reciprocal, unit: .degrees)
    )

    // Find arc segment points: skip origin and initial-fix-segment points, and last point (snapped to fix)
    // Arc points should be the ones generated by the arc segment
    // Since we have a stepped path, find points that are roughly at arc radius from center
    let arcPoints = path.points.filter { point in
      let dist = GeoCalculations.distanceNM(from: center, to: point.coordinate)
      return dist.isApproximatelyEqual(to: arcRadiusNM, relativeTolerance: 0.05)
    }
    #expect(arcPoints.count > 2)
    for point in arcPoints {
      let distFromCenter = GeoCalculations.distanceNM(from: center, to: point.coordinate)
      #expect(distFromCenter.isApproximatelyEqual(to: arcRadiusNM, relativeTolerance: 0.05))
    }
  }

  @Test
  func radiusToFixEndpointMatchesFix() throws {
    let initialFix = Helper.createTestLeg(
      identifier: "START",
      latitude: 37.40,
      longitude: -122.00,
      legType: .initialFix,
      sequenceIndex: 0
    )
    let endLat = 37.42
    let endLon = -121.98
    let arcFix = Helper.createTestLeg(
      identifier: "ARC",
      latitude: endLat,
      longitude: endLon,
      legType: .radiusToFix(
        arcRadius: .init(value: 5, unit: .nauticalMiles),
        course: .init(value: 180, unit: .degrees)
      ),
      sequenceIndex: 1
    )
    let path = try #require(
      ProcedurePathGenerator(
        climbProfile: climbProfile,
        schedule: .init(segments: [.init(profile: .enroute(antiIce: false))]),
        magneticVariation: magneticVariation
      ).departurePath(
        from: [initialFix, arcFix],
        takeoffPoint: takeoffPoint,
        takeoffPointAltitudeFt: takeoffAltitudeFt
      )
    )
    let lastPoint = path.points.last
    #expect(
      lastPoint?.coordinate.latitude.isApproximatelyEqual(to: endLat, absoluteTolerance: 0.001)
        == true
    )
    #expect(
      lastPoint?.coordinate.longitude.isApproximatelyEqual(to: endLon, absoluteTolerance: 0.001)
        == true
    )
  }

  // MARK: - Missed Approach Path

  @Test
  func missedApproachPathBasic() throws {
    let fix = Helper.createTestLeg(
      identifier: "MAHF",
      latitude: 37.40,
      longitude: -122.00,
      legType: .initialFix,
      sequenceIndex: 0
    )
    let path = try #require(
      ProcedurePathGenerator(
        climbProfile: climbProfile,
        schedule: .init(segments: [.init(profile: .enroute(antiIce: false))]),
        magneticVariation: magneticVariation
      ).missedApproachPath(
        from: [fix],
        startCoordinate: takeoffPoint,
        startAltitudeFt: 1000
      )
    )
    // Origin + intermediate steps + fix = many points
    #expect(path.points.count >= 2)
    // Origin should be prepended
    #expect(path.points[0].distanceNM.isApproximatelyEqual(to: 0, absoluteTolerance: 0.001))
    #expect(path.points[0].altitudeFt.isApproximatelyEqual(to: 1000, absoluteTolerance: 0.001))
  }

  @Test
  func missedApproachPathEmptyFixes() {
    let result = ProcedurePathGenerator(
      climbProfile: climbProfile,
      schedule: .init(segments: [.init(profile: .enroute(antiIce: false))]),
      magneticVariation: magneticVariation
    ).missedApproachPath(
      from: [],
      startCoordinate: takeoffPoint,
      startAltitudeFt: 1000
    )
    #expect(result == nil)
  }

  // MARK: - Heading-To-Altitude Wind Correction

  @Test
  func headingToAltitudeNoWindSameAsBefore() throws {
    // Zero wind should produce identical result to the old toAltitudeSegment behavior
    let startCoord = CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0)
    let profile = Helper.createTestClimbProfile(gradientFtPerNM: 300)

    let fix = Helper.createTestLeg(
      identifier: "IF",
      latitude: startCoord.latitude,
      longitude: startCoord.longitude,
      legType: .initialFix,
      sequenceIndex: 0
    )
    let haFix = Helper.createTestLeg(
      identifier: "HA",
      latitude: startCoord.latitude,
      longitude: startCoord.longitude,
      altitudeRestriction: .at(.init(value: 5000, unit: .feet)),
      legType: .headingToAltitude(heading: .init(value: 360, unit: .degrees)),
      sequenceIndex: 1
    )
    // Also create equivalent courseToAltitude for comparison
    let caFix = Helper.createTestLeg(
      identifier: "CA",
      latitude: startCoord.latitude,
      longitude: startCoord.longitude,
      altitudeRestriction: .at(.init(value: 5000, unit: .feet)),
      legType: .courseToAltitude(course: .init(value: 360, unit: .degrees)),
      sequenceIndex: 1
    )

    let haPath = try #require(
      ProcedurePathGenerator(
        climbProfile: profile,
        schedule: .init(segments: [.init(profile: .enroute(antiIce: false))]),
        magneticVariation: magneticVariation
      ).departurePath(
        from: [fix, haFix],
        takeoffPoint: startCoord,
        takeoffPointAltitudeFt: 0
      )
    )
    let caPath = try #require(
      ProcedurePathGenerator(
        climbProfile: profile,
        schedule: .init(segments: [.init(profile: .enroute(antiIce: false))]),
        magneticVariation: magneticVariation
      ).departurePath(
        from: [fix, caFix],
        takeoffPoint: startCoord,
        takeoffPointAltitudeFt: 0
      )
    )

    // Endpoints should be very close (both zero-wind along same direction)
    let haEnd = haPath.points.last!.coordinate
    let caEnd = caPath.points.last!.coordinate
    #expect(
      haEnd.latitude.isApproximatelyEqual(to: caEnd.latitude, absoluteTolerance: 0.01)
    )
    #expect(
      haEnd.longitude.isApproximatelyEqual(to: caEnd.longitude, absoluteTolerance: 0.01)
    )
  }

  @Test
  func headingToAltitudeWithHeadwind() throws {
    // Direct headwind: ground distance should be shorter than air distance
    let startCoord = CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0)
    // Heading 360 (north), wind from 360 (headwind)
    let windProfile = Helper.createTestClimbProfile(
      gradientFtPerNM: 300,
      windDirectionDeg: 360,
      windSpeedKts: 30
    )
    let noWindProfile = Helper.createTestClimbProfile(gradientFtPerNM: 300)

    let fix = Helper.createTestLeg(
      identifier: "IF",
      latitude: startCoord.latitude,
      longitude: startCoord.longitude,
      legType: .initialFix,
      sequenceIndex: 0
    )
    let haFix = Helper.createTestLeg(
      identifier: "HA",
      latitude: startCoord.latitude,
      longitude: startCoord.longitude,
      altitudeRestriction: .at(.init(value: 5000, unit: .feet)),
      legType: .headingToAltitude(heading: .init(value: 14, unit: .degrees)),
      sequenceIndex: 1
    )

    let windPath = try #require(
      ProcedurePathGenerator(
        climbProfile: windProfile,
        schedule: .init(segments: [.init(profile: .enroute(antiIce: false))]),
        magneticVariation: magneticVariation
      ).departurePath(
        from: [fix, haFix],
        takeoffPoint: startCoord,
        takeoffPointAltitudeFt: 0
      )
    )
    let noWindPath = try #require(
      ProcedurePathGenerator(
        climbProfile: noWindProfile,
        schedule: .init(segments: [.init(profile: .enroute(antiIce: false))]),
        magneticVariation: magneticVariation
      ).departurePath(
        from: [fix, haFix],
        takeoffPoint: startCoord,
        takeoffPointAltitudeFt: 0
      )
    )

    // Headwind reduces ground distance
    let windDist = windPath.points.last!.distanceNM
    let noWindDist = noWindPath.points.last!.distanceNM
    #expect(windDist < noWindDist)
  }

  @Test
  func headingToAltitudeWithTailwind() throws {
    // Direct tailwind: ground distance should be longer than air distance
    let startCoord = CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0)
    // Heading 360 true (mag 14 with -14 variation), wind from 180 (tailwind)
    let windProfile = Helper.createTestClimbProfile(
      gradientFtPerNM: 300,
      windDirectionDeg: 180,
      windSpeedKts: 30
    )
    let noWindProfile = Helper.createTestClimbProfile(gradientFtPerNM: 300)

    let fix = Helper.createTestLeg(
      identifier: "IF",
      latitude: startCoord.latitude,
      longitude: startCoord.longitude,
      legType: .initialFix,
      sequenceIndex: 0
    )
    let haFix = Helper.createTestLeg(
      identifier: "HA",
      latitude: startCoord.latitude,
      longitude: startCoord.longitude,
      altitudeRestriction: .at(.init(value: 5000, unit: .feet)),
      legType: .headingToAltitude(heading: .init(value: 14, unit: .degrees)),
      sequenceIndex: 1
    )

    let windPath = try #require(
      ProcedurePathGenerator(
        climbProfile: windProfile,
        schedule: .init(segments: [.init(profile: .enroute(antiIce: false))]),
        magneticVariation: magneticVariation
      ).departurePath(
        from: [fix, haFix],
        takeoffPoint: startCoord,
        takeoffPointAltitudeFt: 0
      )
    )
    let noWindPath = try #require(
      ProcedurePathGenerator(
        climbProfile: noWindProfile,
        schedule: .init(segments: [.init(profile: .enroute(antiIce: false))]),
        magneticVariation: magneticVariation
      ).departurePath(
        from: [fix, haFix],
        takeoffPoint: startCoord,
        takeoffPointAltitudeFt: 0
      )
    )

    // Tailwind increases ground distance
    let windDist = windPath.points.last!.distanceNM
    let noWindDist = noWindPath.points.last!.distanceNM
    #expect(windDist > noWindDist)
  }

  @Test
  func headingToAltitudeWithCrosswind() throws {
    // Pure crosswind: endpoint should be offset laterally from zero-wind path
    let startCoord = CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0)
    // Heading 360 true (mag 14), wind from 270 (left crosswind, pushes east)
    let windProfile = Helper.createTestClimbProfile(
      gradientFtPerNM: 300,
      windDirectionDeg: 270,
      windSpeedKts: 30
    )
    let noWindProfile = Helper.createTestClimbProfile(gradientFtPerNM: 300)

    let fix = Helper.createTestLeg(
      identifier: "IF",
      latitude: startCoord.latitude,
      longitude: startCoord.longitude,
      legType: .initialFix,
      sequenceIndex: 0
    )
    let haFix = Helper.createTestLeg(
      identifier: "HA",
      latitude: startCoord.latitude,
      longitude: startCoord.longitude,
      altitudeRestriction: .at(.init(value: 5000, unit: .feet)),
      legType: .headingToAltitude(heading: .init(value: 14, unit: .degrees)),
      sequenceIndex: 1
    )

    let windPath = try #require(
      ProcedurePathGenerator(
        climbProfile: windProfile,
        schedule: .init(segments: [.init(profile: .enroute(antiIce: false))]),
        magneticVariation: magneticVariation
      ).departurePath(
        from: [fix, haFix],
        takeoffPoint: startCoord,
        takeoffPointAltitudeFt: 0
      )
    )
    let noWindPath = try #require(
      ProcedurePathGenerator(
        climbProfile: noWindProfile,
        schedule: .init(segments: [.init(profile: .enroute(antiIce: false))]),
        magneticVariation: magneticVariation
      ).departurePath(
        from: [fix, haFix],
        takeoffPoint: startCoord,
        takeoffPointAltitudeFt: 0
      )
    )

    let windEnd = windPath.points.last!.coordinate
    let noWindEnd = noWindPath.points.last!.coordinate

    // Wind from 270 (west) pushes aircraft east — longitude should be higher (less negative)
    #expect(windEnd.longitude > noWindEnd.longitude)
  }

  // MARK: - Course-To-Altitude Wind Correction

  @Test
  func courseToAltitudeWithHeadwind() throws {
    let startCoord = CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0)
    // Course 360 true (mag 14 with -14 variation), wind from 360 (headwind)
    let windProfile = Helper.createTestClimbProfile(
      gradientFtPerNM: 300,
      windDirectionDeg: 360,
      windSpeedKts: 30
    )
    let noWindProfile = Helper.createTestClimbProfile(gradientFtPerNM: 300)

    let fix = Helper.createTestLeg(
      identifier: "IF",
      latitude: startCoord.latitude,
      longitude: startCoord.longitude,
      legType: .initialFix,
      sequenceIndex: 0
    )
    let caFix = Helper.createTestLeg(
      identifier: "CA",
      latitude: startCoord.latitude,
      longitude: startCoord.longitude,
      altitudeRestriction: .at(.init(value: 5000, unit: .feet)),
      legType: .courseToAltitude(course: .init(value: 14, unit: .degrees)),
      sequenceIndex: 1
    )

    let windPath = try #require(
      ProcedurePathGenerator(
        climbProfile: windProfile,
        schedule: .init(segments: [.init(profile: .enroute(antiIce: false))]),
        magneticVariation: magneticVariation
      ).departurePath(
        from: [fix, caFix],
        takeoffPoint: startCoord,
        takeoffPointAltitudeFt: 0
      )
    )
    let noWindPath = try #require(
      ProcedurePathGenerator(
        climbProfile: noWindProfile,
        schedule: .init(segments: [.init(profile: .enroute(antiIce: false))]),
        magneticVariation: magneticVariation
      ).departurePath(
        from: [fix, caFix],
        takeoffPoint: startCoord,
        takeoffPointAltitudeFt: 0
      )
    )

    let windDist = windPath.points.last!.distanceNM
    let noWindDist = noWindPath.points.last!.distanceNM
    #expect(windDist < noWindDist)
  }

  @Test
  func courseToAltitudeWithTailwind() throws {
    let startCoord = CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0)
    let windProfile = Helper.createTestClimbProfile(
      gradientFtPerNM: 300,
      windDirectionDeg: 180,
      windSpeedKts: 30
    )
    let noWindProfile = Helper.createTestClimbProfile(gradientFtPerNM: 300)

    let fix = Helper.createTestLeg(
      identifier: "IF",
      latitude: startCoord.latitude,
      longitude: startCoord.longitude,
      legType: .initialFix,
      sequenceIndex: 0
    )
    let caFix = Helper.createTestLeg(
      identifier: "CA",
      latitude: startCoord.latitude,
      longitude: startCoord.longitude,
      altitudeRestriction: .at(.init(value: 5000, unit: .feet)),
      legType: .courseToAltitude(course: .init(value: 14, unit: .degrees)),
      sequenceIndex: 1
    )

    let windPath = try #require(
      ProcedurePathGenerator(
        climbProfile: windProfile,
        schedule: .init(segments: [.init(profile: .enroute(antiIce: false))]),
        magneticVariation: magneticVariation
      ).departurePath(
        from: [fix, caFix],
        takeoffPoint: startCoord,
        takeoffPointAltitudeFt: 0
      )
    )
    let noWindPath = try #require(
      ProcedurePathGenerator(
        climbProfile: noWindProfile,
        schedule: .init(segments: [.init(profile: .enroute(antiIce: false))]),
        magneticVariation: magneticVariation
      ).departurePath(
        from: [fix, caFix],
        takeoffPoint: startCoord,
        takeoffPointAltitudeFt: 0
      )
    )

    let windDist = windPath.points.last!.distanceNM
    let noWindDist = noWindPath.points.last!.distanceNM
    #expect(windDist > noWindDist)
  }

  @Test
  func courseToAltitudeTrackUnchangedWithCrosswind() throws {
    // Course-based legs crab to maintain course, so crosswind should NOT drift laterally
    let startCoord = CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0)
    // Wind from 270 (west, pushes east)
    let windProfile = Helper.createTestClimbProfile(
      gradientFtPerNM: 300,
      windDirectionDeg: 270,
      windSpeedKts: 30
    )
    let noWindProfile = Helper.createTestClimbProfile(gradientFtPerNM: 300)

    let fix = Helper.createTestLeg(
      identifier: "IF",
      latitude: startCoord.latitude,
      longitude: startCoord.longitude,
      legType: .initialFix,
      sequenceIndex: 0
    )
    let caFix = Helper.createTestLeg(
      identifier: "CA",
      latitude: startCoord.latitude,
      longitude: startCoord.longitude,
      altitudeRestriction: .at(.init(value: 5000, unit: .feet)),
      legType: .courseToAltitude(course: .init(value: 14, unit: .degrees)),
      sequenceIndex: 1
    )

    let windPath = try #require(
      ProcedurePathGenerator(
        climbProfile: windProfile,
        schedule: .init(segments: [.init(profile: .enroute(antiIce: false))]),
        magneticVariation: magneticVariation
      ).departurePath(
        from: [fix, caFix],
        takeoffPoint: startCoord,
        takeoffPointAltitudeFt: 0
      )
    )
    let noWindPath = try #require(
      ProcedurePathGenerator(
        climbProfile: noWindProfile,
        schedule: .init(segments: [.init(profile: .enroute(antiIce: false))]),
        magneticVariation: magneticVariation
      ).departurePath(
        from: [fix, caFix],
        takeoffPoint: startCoord,
        takeoffPointAltitudeFt: 0
      )
    )

    let windEnd = windPath.points.last!.coordinate
    let noWindEnd = noWindPath.points.last!.coordinate

    // Longitude should be essentially unchanged (course-based, no lateral drift)
    #expect(
      windEnd.longitude.isApproximatelyEqual(to: noWindEnd.longitude, absoluteTolerance: 0.001)
    )
  }

  // MARK: - DME Termination Tests

  @Test
  func courseToDMEBasic() throws {
    // Fly north from start, navaid to the south; DME 10 NM
    let startCoord = CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0)
    let navaidCoord = CLLocationCoordinate2D(latitude: 36.9, longitude: -122.0)
    let navaid = Helper.createTestNavaid(
      latitude: navaidCoord.latitude,
      longitude: navaidCoord.longitude
    )

    let fix = Helper.createTestLeg(
      identifier: "IF",
      latitude: startCoord.latitude,
      longitude: startCoord.longitude,
      legType: .initialFix,
      sequenceIndex: 0
    )
    let dmeLeg = Helper.createTestLeg(
      identifier: "CD",
      latitude: startCoord.latitude,
      longitude: startCoord.longitude,
      legType: .courseToDME(course: .init(value: 14, unit: .degrees)),
      sequenceIndex: 1,
      navaid: navaid,
      dmeDistance: .init(value: 10, unit: .nauticalMiles)
    )

    let path = try #require(
      ProcedurePathGenerator(
        climbProfile: climbProfile,
        schedule: .init(segments: [.init(profile: .enroute(antiIce: false))]),
        magneticVariation: magneticVariation
      ).departurePath(
        from: [fix, dmeLeg],
        takeoffPoint: startCoord,
        takeoffPointAltitudeFt: 0
      )
    )

    let endpoint = path.points.last!.coordinate
    let distFromNavaid = GeoCalculations.distanceNM(from: endpoint, to: navaidCoord)
    #expect(distFromNavaid.isApproximatelyEqual(to: 10, absoluteTolerance: 0.2))
  }

  @Test
  func courseToDMESlantRangeCorrection() throws {
    let startCoord = CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0)
    let navaidCoord = CLLocationCoordinate2D(latitude: 36.9, longitude: -122.0)
    // Navaid at 1000 ft elevation — slant range > ground distance
    let navaidWithElev = Helper.createTestNavaid(
      latitude: navaidCoord.latitude,
      longitude: navaidCoord.longitude,
      elevation: 1000
    )
    let navaidNoElev = Helper.createTestNavaid(
      latitude: navaidCoord.latitude,
      longitude: navaidCoord.longitude
    )

    let fix = Helper.createTestLeg(
      identifier: "IF",
      latitude: startCoord.latitude,
      longitude: startCoord.longitude,
      legType: .initialFix,
      sequenceIndex: 0
    )
    let dmeLegWithElev = Helper.createTestLeg(
      identifier: "CD",
      latitude: startCoord.latitude,
      longitude: startCoord.longitude,
      legType: .courseToDME(course: .init(value: 14, unit: .degrees)),
      sequenceIndex: 1,
      navaid: navaidWithElev,
      dmeDistance: .init(value: 10, unit: .nauticalMiles)
    )
    let dmeLegNoElev = Helper.createTestLeg(
      identifier: "CD",
      latitude: startCoord.latitude,
      longitude: startCoord.longitude,
      legType: .courseToDME(course: .init(value: 14, unit: .degrees)),
      sequenceIndex: 1,
      navaid: navaidNoElev,
      dmeDistance: .init(value: 10, unit: .nauticalMiles)
    )

    let pathWithElev = try #require(
      ProcedurePathGenerator(
        climbProfile: climbProfile,
        schedule: .init(segments: [.init(profile: .enroute(antiIce: false))]),
        magneticVariation: magneticVariation
      ).departurePath(
        from: [fix, dmeLegWithElev],
        takeoffPoint: startCoord,
        takeoffPointAltitudeFt: 0
      )
    )
    let pathNoElev = try #require(
      ProcedurePathGenerator(
        climbProfile: climbProfile,
        schedule: .init(segments: [.init(profile: .enroute(antiIce: false))]),
        magneticVariation: magneticVariation
      ).departurePath(
        from: [fix, dmeLegNoElev],
        takeoffPoint: startCoord,
        takeoffPointAltitudeFt: 0
      )
    )

    let distWithElev = GeoCalculations.distanceNM(
      from: pathWithElev.points.last!.coordinate,
      to: navaidCoord
    )
    let distNoElev = GeoCalculations.distanceNM(
      from: pathNoElev.points.last!.coordinate,
      to: navaidCoord
    )

    // With elevation known, ground distance < slant range, so endpoint should be closer
    #expect(distWithElev < distNoElev)
  }

  @Test
  func courseToDMENoNavaidReturnsNil() {
    let fix = Helper.createTestLeg(
      legType: .courseToDME(course: .init(value: 360, unit: .degrees)),
      sequenceIndex: 0,
      dmeDistance: .init(value: 10, unit: .nauticalMiles)
    )
    let result = ProcedurePathGenerator(
      climbProfile: climbProfile,
      schedule: .init(segments: [.init(profile: .enroute(antiIce: false))]),
      magneticVariation: magneticVariation
    ).departurePath(
      from: [fix],
      takeoffPoint: takeoffPoint,
      takeoffPointAltitudeFt: takeoffAltitudeFt
    )
    #expect(result == nil)
  }

  @Test
  func courseToDMENoDmeDistanceReturnsNil() {
    let navaid = Helper.createTestNavaid()
    let fix = Helper.createTestLeg(
      legType: .courseToDME(course: .init(value: 360, unit: .degrees)),
      sequenceIndex: 0,
      navaid: navaid
    )
    let result = ProcedurePathGenerator(
      climbProfile: climbProfile,
      schedule: .init(segments: [.init(profile: .enroute(antiIce: false))]),
      magneticVariation: magneticVariation
    ).departurePath(
      from: [fix],
      takeoffPoint: takeoffPoint,
      takeoffPointAltitudeFt: takeoffAltitudeFt
    )
    #expect(result == nil)
  }

  @Test
  func headingToDMEBasic() throws {
    let startCoord = CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0)
    let navaidCoord = CLLocationCoordinate2D(latitude: 36.9, longitude: -122.0)
    let navaid = Helper.createTestNavaid(
      latitude: navaidCoord.latitude,
      longitude: navaidCoord.longitude
    )

    let fix = Helper.createTestLeg(
      identifier: "IF",
      latitude: startCoord.latitude,
      longitude: startCoord.longitude,
      legType: .initialFix,
      sequenceIndex: 0
    )
    let dmeLeg = Helper.createTestLeg(
      identifier: "VD",
      latitude: startCoord.latitude,
      longitude: startCoord.longitude,
      legType: .headingToDME(heading: .init(value: 14, unit: .degrees)),
      sequenceIndex: 1,
      navaid: navaid,
      dmeDistance: .init(value: 10, unit: .nauticalMiles)
    )

    let path = try #require(
      ProcedurePathGenerator(
        climbProfile: climbProfile,
        schedule: .init(segments: [.init(profile: .enroute(antiIce: false))]),
        magneticVariation: magneticVariation
      ).departurePath(
        from: [fix, dmeLeg],
        takeoffPoint: startCoord,
        takeoffPointAltitudeFt: 0
      )
    )

    let endpoint = path.points.last!.coordinate
    let distFromNavaid = GeoCalculations.distanceNM(from: endpoint, to: navaidCoord)
    #expect(distFromNavaid.isApproximatelyEqual(to: 10, absoluteTolerance: 0.2))
  }

  @Test
  func headingToDMECrosswindDrift() throws {
    let startCoord = CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0)
    let navaidCoord = CLLocationCoordinate2D(latitude: 36.9, longitude: -122.0)

    let windProfile = Helper.createTestClimbProfile(
      gradientFtPerNM: 300,
      windDirectionDeg: 270,
      windSpeedKts: 30
    )
    let noWindProfile = Helper.createTestClimbProfile(gradientFtPerNM: 300)

    let navaid = Helper.createTestNavaid(
      latitude: navaidCoord.latitude,
      longitude: navaidCoord.longitude
    )

    let fix = Helper.createTestLeg(
      identifier: "IF",
      latitude: startCoord.latitude,
      longitude: startCoord.longitude,
      legType: .initialFix,
      sequenceIndex: 0
    )
    let dmeLeg = Helper.createTestLeg(
      identifier: "VD",
      latitude: startCoord.latitude,
      longitude: startCoord.longitude,
      legType: .headingToDME(heading: .init(value: 14, unit: .degrees)),
      sequenceIndex: 1,
      navaid: navaid,
      dmeDistance: .init(value: 10, unit: .nauticalMiles)
    )

    let windPath = try #require(
      ProcedurePathGenerator(
        climbProfile: windProfile,
        schedule: .init(segments: [.init(profile: .enroute(antiIce: false))]),
        magneticVariation: magneticVariation
      ).departurePath(
        from: [fix, dmeLeg],
        takeoffPoint: startCoord,
        takeoffPointAltitudeFt: 0
      )
    )
    let noWindPath = try #require(
      ProcedurePathGenerator(
        climbProfile: noWindProfile,
        schedule: .init(segments: [.init(profile: .enroute(antiIce: false))]),
        magneticVariation: magneticVariation
      ).departurePath(
        from: [fix, dmeLeg],
        takeoffPoint: startCoord,
        takeoffPointAltitudeFt: 0
      )
    )

    let windEnd = windPath.points.last!.coordinate
    let noWindEnd = noWindPath.points.last!.coordinate

    // Wind from west pushes heading-based flight east
    #expect(windEnd.longitude > noWindEnd.longitude)
  }

  @Test
  func trackFromFixDMEBasic() throws {
    // Fix at 37.0, -122.0; navaid at 36.9, -122.0 (south); fly north from fix
    let fixCoord = CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0)
    let navaidCoord = CLLocationCoordinate2D(latitude: 36.9, longitude: -122.0)
    let navaid = Helper.createTestNavaid(
      latitude: navaidCoord.latitude,
      longitude: navaidCoord.longitude
    )

    let initialFix = Helper.createTestLeg(
      identifier: "IF",
      latitude: fixCoord.latitude,
      longitude: fixCoord.longitude,
      legType: .initialFix,
      sequenceIndex: 0
    )
    let fdLeg = Helper.createTestLeg(
      identifier: "FD",
      latitude: fixCoord.latitude,
      longitude: fixCoord.longitude,
      legType: .trackFromFixDME(course: .init(value: 14, unit: .degrees)),
      sequenceIndex: 1,
      navaid: navaid,
      dmeDistance: .init(value: 10, unit: .nauticalMiles)
    )

    let path = try #require(
      ProcedurePathGenerator(
        climbProfile: climbProfile,
        schedule: .init(segments: [.init(profile: .enroute(antiIce: false))]),
        magneticVariation: magneticVariation
      ).departurePath(
        from: [initialFix, fdLeg],
        takeoffPoint: fixCoord,
        takeoffPointAltitudeFt: 0
      )
    )

    let endpoint = path.points.last!.coordinate
    let distFromNavaid = GeoCalculations.distanceNM(from: endpoint, to: navaidCoord)
    #expect(distFromNavaid.isApproximatelyEqual(to: 10, absoluteTolerance: 0.2))
  }

  @Test
  func trackFromFixDistanceBasic() throws {
    let fixCoord = CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0)

    let initialFix = Helper.createTestLeg(
      identifier: "IF",
      latitude: fixCoord.latitude,
      longitude: fixCoord.longitude,
      legType: .initialFix,
      sequenceIndex: 0
    )
    let fcLeg = Helper.createTestLeg(
      identifier: "FC",
      latitude: fixCoord.latitude,
      longitude: fixCoord.longitude,
      legType: .trackFromFixDistance(course: .init(value: 14, unit: .degrees)),
      sequenceIndex: 1,
      dmeDistance: .init(value: 5, unit: .nauticalMiles)
    )

    let path = try #require(
      ProcedurePathGenerator(
        climbProfile: climbProfile,
        schedule: .init(segments: [.init(profile: .enroute(antiIce: false))]),
        magneticVariation: magneticVariation
      ).departurePath(
        from: [initialFix, fcLeg],
        takeoffPoint: fixCoord,
        takeoffPointAltitudeFt: 0
      )
    )

    let endpoint = path.points.last!.coordinate
    let distFromFix = GeoCalculations.distanceNM(from: fixCoord, to: endpoint)
    #expect(distFromFix.isApproximatelyEqual(to: 5, absoluteTolerance: 0.15))
  }

  @Test
  func trackFromFixDistanceAltitude() throws {
    // With headwind, aircraft covers more air distance per ground distance,
    // so altitude at endpoint should be higher
    let fixCoord = CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0)
    let windProfile = Helper.createTestClimbProfile(
      gradientFtPerNM: 300,
      windDirectionDeg: 360,
      windSpeedKts: 30
    )
    let noWindProfile = Helper.createTestClimbProfile(gradientFtPerNM: 300)

    let initialFix = Helper.createTestLeg(
      identifier: "IF",
      latitude: fixCoord.latitude,
      longitude: fixCoord.longitude,
      legType: .initialFix,
      sequenceIndex: 0
    )
    let fcLeg = Helper.createTestLeg(
      identifier: "FC",
      latitude: fixCoord.latitude,
      longitude: fixCoord.longitude,
      legType: .trackFromFixDistance(course: .init(value: 14, unit: .degrees)),
      sequenceIndex: 1,
      dmeDistance: .init(value: 5, unit: .nauticalMiles)
    )

    let windPath = try #require(
      ProcedurePathGenerator(
        climbProfile: windProfile,
        schedule: .init(segments: [.init(profile: .enroute(antiIce: false))]),
        magneticVariation: magneticVariation
      ).departurePath(
        from: [initialFix, fcLeg],
        takeoffPoint: fixCoord,
        takeoffPointAltitudeFt: 0
      )
    )
    let noWindPath = try #require(
      ProcedurePathGenerator(
        climbProfile: noWindProfile,
        schedule: .init(segments: [.init(profile: .enroute(antiIce: false))]),
        magneticVariation: magneticVariation
      ).departurePath(
        from: [initialFix, fcLeg],
        takeoffPoint: fixCoord,
        takeoffPointAltitudeFt: 0
      )
    )

    // Headwind means more air distance for same ground distance, so higher altitude
    let windAlt = windPath.points.last!.altitudeFt
    let noWindAlt = noWindPath.points.last!.altitudeFt
    #expect(windAlt > noWindAlt)

    // Both should cover same ground distance (5 NM)
    let windDist = windPath.points.last!.distanceNM
    let noWindDist = noWindPath.points.last!.distanceNM
    #expect(
      windDist.isApproximatelyEqual(to: noWindDist, absoluteTolerance: 0.2)
    )
  }

  // MARK: - Multi-Leg Integration

  @Test
  func multiLegDeparture() throws {
    let fixes = [
      Helper.createTestLeg(
        identifier: "IF",
        latitude: 37.38,
        longitude: -121.95,
        legType: .initialFix,
        sequenceIndex: 0
      ),
      Helper.createTestLeg(
        identifier: "TF",
        latitude: 37.42,
        longitude: -122.00,
        legType: .trackToFix(course: .init(value: 300, unit: .degrees)),
        sequenceIndex: 1
      ),
      Helper.createTestLeg(
        identifier: "FA",
        latitude: 37.42,
        longitude: -122.00,
        altitudeRestriction: .at(.init(value: 5000, unit: .feet)),
        legType: .fixToAltitude(course: .init(value: 300, unit: .degrees)),
        sequenceIndex: 2
      )
    ]

    let path = try #require(
      ProcedurePathGenerator(
        climbProfile: climbProfile,
        schedule: .init(segments: [.init(profile: .enroute(antiIce: false))]),
        magneticVariation: magneticVariation
      ).departurePath(
        from: fixes,
        takeoffPoint: takeoffPoint,
        takeoffPointAltitudeFt: takeoffAltitudeFt
      )
    )

    // Many intermediate points now (origin + stepped segments)
    #expect(path.points.count > 4)
    // Monotonic distances
    for i in 1..<path.points.count {
      #expect(path.points[i].distanceNM > path.points[i - 1].distanceNM)
    }
    // Final altitude should be at the target
    #expect(
      path.points.last?.altitudeFt.isApproximatelyEqual(to: 5000, absoluteTolerance: 1) == true
    )
  }

  // MARK: - Altitude Tests (new for stepped model)

  @Test
  func altitudeIncreasesMonotonically() throws {
    let startCoord = CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0)
    let fix = Helper.createTestLeg(
      identifier: "IF",
      latitude: startCoord.latitude,
      longitude: startCoord.longitude,
      legType: .initialFix,
      sequenceIndex: 0
    )
    let faFix = Helper.createTestLeg(
      identifier: "FA",
      latitude: startCoord.latitude,
      longitude: startCoord.longitude,
      altitudeRestriction: .at(.init(value: 5000, unit: .feet)),
      legType: .fixToAltitude(course: .init(value: 360, unit: .degrees)),
      sequenceIndex: 1
    )
    let path = try #require(
      ProcedurePathGenerator(
        climbProfile: climbProfile,
        schedule: .init(segments: [.init(profile: .enroute(antiIce: false))]),
        magneticVariation: magneticVariation
      ).departurePath(
        from: [fix, faFix],
        takeoffPoint: startCoord,
        takeoffPointAltitudeFt: 0
      )
    )
    for i in 1..<path.points.count {
      #expect(path.points[i].altitudeFt >= path.points[i - 1].altitudeFt)
    }
  }

  @Test
  func intermediatePointDensity() throws {
    // A 5 NM leg should produce roughly 50 intermediate points (one per 0.1 NM)
    // plus start and final
    let startCoord = CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0)
    // Place fix ~5 NM north (about 0.083° latitude)
    let fixCoord = CLLocationCoordinate2D(latitude: 37.083, longitude: -122.0)
    let fix = Helper.createTestLeg(
      identifier: "TF",
      latitude: fixCoord.latitude,
      longitude: fixCoord.longitude,
      legType: .trackToFix(course: .init(value: 360, unit: .degrees)),
      sequenceIndex: 0
    )
    let path = try #require(
      ProcedurePathGenerator(
        climbProfile: climbProfile,
        schedule: .init(segments: [.init(profile: .enroute(antiIce: false))]),
        magneticVariation: magneticVariation
      ).departurePath(
        from: [fix],
        takeoffPoint: startCoord,
        takeoffPointAltitudeFt: 0
      )
    )
    // Expect roughly 10 points per NM (0.1 NM step) plus origin
    let totalNM = path.totalDistanceNM
    let expectedPoints = Int(totalNM / 0.1) + 1  // +1 for origin
    // Allow 20% tolerance
    #expect(path.points.count > expectedPoints * 8 / 10)
  }

  @Test
  func headwindProducesHigherAltitudeAtSameGroundDistance() throws {
    // For a fixed ground distance leg, headwind means more air distance → more climb
    let fixCoord = CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0)
    let endCoord = CLLocationCoordinate2D(latitude: 37.083, longitude: -122.0)  // ~5 NM north
    let windProfile = Helper.createTestClimbProfile(
      gradientFtPerNM: 300,
      windDirectionDeg: 360,
      windSpeedKts: 30
    )
    let noWindProfile = Helper.createTestClimbProfile(gradientFtPerNM: 300)

    let fix = Helper.createTestLeg(
      identifier: "TF",
      latitude: endCoord.latitude,
      longitude: endCoord.longitude,
      legType: .trackToFix(course: .init(value: 360, unit: .degrees)),
      sequenceIndex: 0
    )

    let windPath = try #require(
      ProcedurePathGenerator(
        climbProfile: windProfile,
        schedule: .init(segments: [.init(profile: .enroute(antiIce: false))]),
        magneticVariation: magneticVariation
      ).departurePath(
        from: [fix],
        takeoffPoint: fixCoord,
        takeoffPointAltitudeFt: 0
      )
    )
    let noWindPath = try #require(
      ProcedurePathGenerator(
        climbProfile: noWindProfile,
        schedule: .init(segments: [.init(profile: .enroute(antiIce: false))]),
        magneticVariation: magneticVariation
      ).departurePath(
        from: [fix],
        takeoffPoint: fixCoord,
        takeoffPointAltitudeFt: 0
      )
    )

    // Same ground distance, but headwind means more air distance → higher altitude
    let windAlt = windPath.points.last!.altitudeFt
    let noWindAlt = noWindPath.points.last!.altitudeFt
    #expect(windAlt > noWindAlt)
  }

  // MARK: - Elapsed Time Tests

  @Test
  func elapsedTimeIncreasesMonotonically() throws {
    let startCoord = CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0)
    let fix = Helper.createTestLeg(
      identifier: "IF",
      latitude: startCoord.latitude,
      longitude: startCoord.longitude,
      legType: .initialFix,
      sequenceIndex: 0
    )
    let faFix = Helper.createTestLeg(
      identifier: "FA",
      latitude: startCoord.latitude,
      longitude: startCoord.longitude,
      altitudeRestriction: .at(.init(value: 5000, unit: .feet)),
      legType: .fixToAltitude(course: .init(value: 360, unit: .degrees)),
      sequenceIndex: 1
    )
    let path = try #require(
      ProcedurePathGenerator(
        climbProfile: climbProfile,
        schedule: .init(segments: [.init(profile: .enroute(antiIce: false))]),
        magneticVariation: magneticVariation
      ).departurePath(
        from: [fix, faFix],
        takeoffPoint: startCoord,
        takeoffPointAltitudeFt: 0
      )
    )
    // Origin should have time 0
    #expect(path.points[0].elapsedTimeSeconds == 0)
    // All subsequent points should have non-decreasing time
    for i in 1..<path.points.count {
      #expect(path.points[i].elapsedTimeSeconds >= path.points[i - 1].elapsedTimeSeconds)
    }
    // Final time should be positive
    #expect(path.points.last!.elapsedTimeSeconds > 0)
    // Points with increasing distance should have increasing time
    for i in 1..<path.points.count
    where path.points[i].distanceNM > path.points[i - 1].distanceNM {
      #expect(path.points[i].elapsedTimeSeconds > path.points[i - 1].elapsedTimeSeconds)
    }
  }

  @Test
  func elapsedTimeMatchesExpectedValue() throws {
    // With constant 300 ft/NM gradient, 170 kt IAS at sea level, no wind:
    // TAS ≈ 170 kt, climbing 5000 ft takes 5000/300 ≈ 16.67 NM air distance
    // At ~170 kt TAS/GS, 16.67 NM takes 16.67/170 * 3600 ≈ 353 seconds
    let startCoord = CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0)
    let fix = Helper.createTestLeg(
      identifier: "IF",
      latitude: startCoord.latitude,
      longitude: startCoord.longitude,
      legType: .initialFix,
      sequenceIndex: 0
    )
    let faFix = Helper.createTestLeg(
      identifier: "FA",
      latitude: startCoord.latitude,
      longitude: startCoord.longitude,
      altitudeRestriction: .at(.init(value: 5000, unit: .feet)),
      legType: .fixToAltitude(course: .init(value: 360, unit: .degrees)),
      sequenceIndex: 1
    )
    let path = try #require(
      ProcedurePathGenerator(
        climbProfile: climbProfile,
        schedule: .init(segments: [.init(profile: .enroute(antiIce: false))]),
        magneticVariation: magneticVariation
      ).departurePath(
        from: [fix, faFix],
        takeoffPoint: startCoord,
        takeoffPointAltitudeFt: 0
      )
    )
    let totalTime = path.points.last!.elapsedTimeSeconds
    // Expected ~353 sec, allow 10% tolerance for TAS variation with altitude
    #expect(totalTime.isApproximatelyEqual(to: 353, relativeTolerance: 0.1))
  }

  // MARK: - Two-Segment Climb Tests

  @Test
  func twoSegmentClimbAltitudeTransition() throws {
    // First segment: takeoff (steep gradient), second: enroute (shallower)
    // With a constant gradient profile this means both segments have same gradient,
    // but we can verify the API works by using different profile types
    let startCoord = CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0)
    let fix = Helper.createTestLeg(
      identifier: "IF",
      latitude: startCoord.latitude,
      longitude: startCoord.longitude,
      legType: .initialFix,
      sequenceIndex: 0
    )
    let faFix = Helper.createTestLeg(
      identifier: "FA",
      latitude: startCoord.latitude,
      longitude: startCoord.longitude,
      altitudeRestriction: .at(.init(value: 5000, unit: .feet)),
      legType: .fixToAltitude(course: .init(value: 360, unit: .degrees)),
      sequenceIndex: 1
    )

    // Single-segment path
    let singlePath = try #require(
      ProcedurePathGenerator(
        climbProfile: climbProfile,
        schedule: .init(segments: [.init(profile: .enroute(antiIce: false))]),
        magneticVariation: magneticVariation
      ).departurePath(
        from: [fix, faFix],
        takeoffPoint: startCoord,
        takeoffPointAltitudeFt: 0
      )
    )

    // Two-segment path (both using same profile type, so results should match)
    let twoSegPath = try #require(
      ProcedurePathGenerator(
        climbProfile: climbProfile,
        schedule: .init(segments: [
          .init(
            profile: .enroute(antiIce: false),
            upperBound: .altitude(.init(value: 2000, unit: .feet))
          ),
          .init(profile: .enroute(antiIce: false))
        ]),
        magneticVariation: magneticVariation
      ).departurePath(
        from: [fix, faFix],
        takeoffPoint: startCoord,
        takeoffPointAltitudeFt: 0
      )
    )

    // Same profile type for both segments → same results
    let singleDist = singlePath.points.last!.distanceNM
    let twoDist = twoSegPath.points.last!.distanceNM
    #expect(singleDist.isApproximatelyEqual(to: twoDist, absoluteTolerance: 0.01))
  }

  @Test
  func twoSegmentClimbTimeTransition() throws {
    let startCoord = CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0)
    let fix = Helper.createTestLeg(
      identifier: "IF",
      latitude: startCoord.latitude,
      longitude: startCoord.longitude,
      legType: .initialFix,
      sequenceIndex: 0
    )
    let faFix = Helper.createTestLeg(
      identifier: "FA",
      latitude: startCoord.latitude,
      longitude: startCoord.longitude,
      altitudeRestriction: .at(.init(value: 5000, unit: .feet)),
      legType: .fixToAltitude(course: .init(value: 360, unit: .degrees)),
      sequenceIndex: 1
    )

    // Two-segment with time-based transition at 60 seconds
    let path = try #require(
      ProcedurePathGenerator(
        climbProfile: climbProfile,
        schedule: .init(segments: [
          .init(
            profile: .enroute(antiIce: false),
            upperBound: .time(.init(value: 60, unit: .seconds))
          ),
          .init(profile: .enroute(antiIce: false))
        ]),
        magneticVariation: magneticVariation
      ).departurePath(
        from: [fix, faFix],
        takeoffPoint: startCoord,
        takeoffPointAltitudeFt: 0
      )
    )

    // Should produce valid path with non-decreasing time and altitude
    #expect(path.points.count > 2)
    for i in 1..<path.points.count {
      #expect(path.points[i].elapsedTimeSeconds >= path.points[i - 1].elapsedTimeSeconds)
      #expect(path.points[i].altitudeFt >= path.points[i - 1].altitudeFt)
    }
    // Final time should be positive
    #expect(path.points.last!.elapsedTimeSeconds > 0)
    #expect(
      path.points.last?.altitudeFt.isApproximatelyEqual(to: 5000, absoluteTolerance: 1) == true
    )
  }
}
