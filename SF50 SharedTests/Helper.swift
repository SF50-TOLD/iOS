import Foundation

@testable import SF50_Shared

enum Helper {

  static func createTestLeg(
    identifier: String? = "FIX",
    latitude: Double? = 37.0,
    longitude: Double? = -122.0,
    altitudeRestriction: AltitudeRestriction? = nil,
    legType: LegType = .initialFix,
    sequenceIndex: Int = 0,
    navaid: Navaid? = nil,
    dmeDistance: Measurement<UnitLength>? = nil,
    theta: Measurement<UnitAngle>? = nil
  ) -> Leg {
    Leg(
      identifier: identifier,
      latitude: latitude.map { Measurement(value: $0, unit: .degrees) },
      longitude: longitude.map { Measurement(value: $0, unit: .degrees) },
      altitudeRestriction: altitudeRestriction,
      legType: legType,
      sequenceIndex: sequenceIndex,
      navaid: navaid,
      dmeDistance: dmeDistance,
      theta: theta
    )
  }

  static func createTestNavaid(
    identifier: String = "TST",
    latitude: Double = 37.0,
    longitude: Double = -122.0,
    elevation: Double? = nil  // feet
  ) -> Navaid {
    Navaid(
      identifier: identifier,
      icaoRegion: "K2",
      type: "VOR/DME",
      latitude: .init(value: latitude, unit: .degrees),
      longitude: .init(value: longitude, unit: .degrees),
      elevation: elevation.map { .init(value: $0, unit: .feet) }
    )
  }

  /// Creates a constant-gradient climb profile for testing.
  /// Default: 300 ft/NM, 170 KIAS, ISA temps, zero wind, 29.92 inHg.
  /// All five profile variants use the same gradient/speed for backward-compatible behavior.
  static func createTestClimbProfile(
    gradientFtPerNM: Double = 300,
    windDirectionDeg: Double = 0,
    windSpeedKts: Double = 0
  ) -> ClimbProfile {
    // ISA standard temps: 15C at sea level, -56.5C at 36,089 ft (lapse rate 1.98C/1000ft)
    let altitudes: [Double] = [0, 5000, 10000, 15000, 20000, 25000, 30000]
    let dataPoints = altitudes.map { alt in
      let climbData = ClimbProfile.ClimbData(
        gradientFtPerNM: .value(gradientFtPerNM),
        indicatedAirspeedKts: .value(170)
      )
      return ClimbProfile.DataPoint(
        altitudeFt: alt,
        outsideAirTemperatureC: 15.0 - alt * 0.00198,
        windDirectionDeg: windDirectionDeg,
        windSpeedKts: windSpeedKts,
        takeoff: climbData,
        enrouteObstacle: climbData,
        enrouteObstacleAntiIce: climbData,
        enroute: climbData,
        enrouteAntiIce: climbData
      )
    }
    return ClimbProfile(dataPoints: dataPoints, seaLevelPressureInHg: 29.92)
  }
}
