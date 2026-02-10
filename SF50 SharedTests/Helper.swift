import Foundation

@testable import SF50_Shared

enum Helper {

  static func createTestConditions(
    temperature: Double? = nil,
    windDirection: Double = 0,
    windSpeed: Double = 0
  ) -> Conditions {
    let temp = temperature.map { Measurement(value: $0, unit: UnitTemperature.celsius) }
    let windDir = Measurement(value: windDirection, unit: UnitAngle.degrees)
    let windSpeedMeasurement = Measurement(value: windSpeed, unit: UnitSpeed.knots)

    return Conditions(
      windDirection: windDir,
      windSpeed: windSpeedMeasurement,
      temperature: temp
    )
  }

  static func createTestConfiguration(
    weight: Double = 6000,
    flapSetting: FlapSetting = .flaps50,
    iceProtection: Bool = false
  ) -> Configuration {
    Configuration(
      weight: Measurement(value: weight, unit: UnitMass.pounds),
      flapSetting: flapSetting,
      iceProtection: iceProtection
    )
  }

  static func createTestAirport(elevation: Double = 0) -> Airport {
    Airport(
      recordID: "TEST",
      locationID: "TEST",
      ICAO_ID: "TEST",
      name: "Test Airport",
      city: "Test City",
      dataSource: .NASR,
      latitude: Measurement(value: 0, unit: .degrees),
      longitude: Measurement(value: 0, unit: .degrees),
      elevation: Measurement(value: elevation, unit: .feet),
      variation: Measurement(value: 0, unit: .degrees)
    )
  }

  static func createTestRunway(
    elevation: Double = 0,
    heading: Double = 360,
    slope: Double = 0,
    isTurf: Bool = false
  ) -> Runway {
    let airport = Self.createTestAirport(elevation: elevation)
    return Runway(
      name: "36",
      elevation: nil,
      trueHeading: Measurement(value: heading, unit: .degrees),
      gradient: Float(slope / 100),
      length: Measurement(value: 5000, unit: .feet),
      takeoffRun: nil,
      takeoffDistance: nil,
      landingDistance: nil,
      isTurf: isTurf,
      airport: airport
    )
  }

  static func createTestRunwayInput(
    elevation: Double = 0,
    heading: Double = 360,
    slope: Double = 0,
    isTurf: Bool = false
  ) -> RunwayInput {
    let runway = Self.createTestRunway(
      elevation: elevation,
      heading: heading,
      slope: slope,
      isTurf: isTurf
    )
    return RunwayInput(from: runway, airport: runway.airport)
  }

  static func createTestLeg(
    identifier: String? = "FIX",
    latitude: Double? = 37.0,
    longitude: Double? = -122.0,
    altitudeRestriction: AltitudeRestriction? = nil,
    legType: LegType = .initialFix,
    sequenceIndex: Int = 0,
    navaid: Navaid? = nil,
    dmeDistance: Measurement<UnitLength>? = nil
  ) -> Leg {
    Leg(
      identifier: identifier,
      latitude: latitude.map { Measurement(value: $0, unit: .degrees) },
      longitude: longitude.map { Measurement(value: $0, unit: .degrees) },
      altitudeRestriction: altitudeRestriction,
      legType: legType,
      sequenceIndex: sequenceIndex,
      navaid: navaid,
      dmeDistance: dmeDistance
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
        gradientFtPerNM: gradientFtPerNM,
        indicatedAirspeedKts: 170
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
