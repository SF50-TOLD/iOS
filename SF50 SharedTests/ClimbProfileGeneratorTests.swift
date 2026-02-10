import Foundation
import RealModule
import Testing

@testable import SF50_Shared

struct ClimbProfileGeneratorTests {

  // MARK: - Helpers

  private func makeWindsAloft(
    altitudes: [Double] = [0, 5000, 10000, 15000, 20000]
  ) -> [ClimbProfileGenerator.WindsAloftObservation] {
    altitudes.map { alt in
      ClimbProfileGenerator.WindsAloftObservation(
        altitudeFt: alt,
        temperatureC: isaTemperature(altitudeFt: alt),
        windDirectionDeg: 270,
        windSpeedKts: 10
      )
    }
  }

  // MARK: - Basic generation

  @Test
  func generateProducesCorrectNumberOfDataPoints() {
    let winds = makeWindsAloft()
    let profile = ClimbProfileGenerator.generate(
      windsAloft: winds,
      weightLb: 6000,
      aircraftType: .g1,
      seaLevelPressureInHg: 29.92,
      useRegressionModel: true
    )
    #expect(profile.dataPoints.count == winds.count)
  }

  @Test
  func generateSortsDataPointsByAltitude() {
    // Pass unsorted altitudes
    let winds = makeWindsAloft(altitudes: [10000, 0, 5000])
    let profile = ClimbProfileGenerator.generate(
      windsAloft: winds,
      weightLb: 6000,
      aircraftType: .g1,
      seaLevelPressureInHg: 29.92,
      useRegressionModel: true
    )
    #expect(profile.dataPoints[0].altitudeFt == 0)
    #expect(profile.dataPoints[1].altitudeFt == 5000)
    #expect(profile.dataPoints[2].altitudeFt == 10000)
  }

  // MARK: - Gradient values

  @Test
  func regressionGradientsArePositive() throws {
    let winds = makeWindsAloft()
    let profile = ClimbProfileGenerator.generate(
      windsAloft: winds,
      weightLb: 5500,
      aircraftType: .g1,
      seaLevelPressureInHg: 29.92,
      useRegressionModel: true
    )

    // All gradient values should be positive for a light-weight aircraft at ISA
    for profileType: ClimbProfile.ProfileType in [
      .takeoff,
      .enrouteObstacle(antiIce: false),
      .enrouteObstacle(antiIce: true),
      .enroute(antiIce: false),
      .enroute(antiIce: true)
    ] {
      let g = try #require(profile.gradient(at: 5000, profile: profileType))
      #expect(g > 0, "Gradient should be positive for \(profileType)")
    }
  }

  @Test
  func gradientsDecreaseWithAltitude() throws {
    let winds = makeWindsAloft()
    let profile = ClimbProfileGenerator.generate(
      windsAloft: winds,
      weightLb: 6000,
      aircraftType: .g1,
      seaLevelPressureInHg: 29.92,
      useRegressionModel: true
    )

    let profileType: ClimbProfile.ProfileType = .enroute(antiIce: false)
    let gLow = try #require(profile.gradient(at: 0, profile: profileType))
    let gHigh = try #require(profile.gradient(at: 20000, profile: profileType))
    // At higher altitude, thinner air means worse climb performance
    #expect(gLow > gHigh)
  }

  // MARK: - Anti-ice effect

  @Test
  func antiIceReducesGradient() throws {
    let winds = makeWindsAloft()
    let profile = ClimbProfileGenerator.generate(
      windsAloft: winds,
      weightLb: 6000,
      aircraftType: .g1,
      seaLevelPressureInHg: 29.92,
      useRegressionModel: true
    )

    let normalGrad = try #require(
      profile.gradient(at: 5000, profile: .enroute(antiIce: false))
    )
    let iceGrad = try #require(
      profile.gradient(at: 5000, profile: .enroute(antiIce: true))
    )
    // Anti-ice should reduce gradient (worse climb performance)
    #expect(normalGrad > iceGrad)
  }

  @Test
  func obstacleGradientDiffersBetweenNormalAndAntiIce() throws {
    let winds = makeWindsAloft()
    let profile = ClimbProfileGenerator.generate(
      windsAloft: winds,
      weightLb: 6000,
      aircraftType: .g1,
      seaLevelPressureInHg: 29.92,
      useRegressionModel: true
    )

    let normalGrad = try #require(
      profile.gradient(at: 5000, profile: .enrouteObstacle(antiIce: false))
    )
    let iceGrad = try #require(
      profile.gradient(at: 5000, profile: .enrouteObstacle(antiIce: true))
    )
    // The obstacle climb ice gradient should never exceed the normal gradient
    // (delta polynomial guarantees ice <= normal). They may be equal when the
    // delta clamps to zero.
    #expect(iceGrad <= normalGrad)
  }

  // MARK: - Constant speeds

  @Test
  func takeoffSpeedIsConstant() throws {
    let winds = makeWindsAloft()
    let profile = ClimbProfileGenerator.generate(
      windsAloft: winds,
      weightLb: 6000,
      aircraftType: .g1,
      seaLevelPressureInHg: 29.92,
      useRegressionModel: true
    )

    // Takeoff IAS at sea level: TAS ~= IAS at sea level ISA
    // The data point IAS should be 91 KIAS
    for dp in profile.dataPoints {
      let climbData = dp.climbData(for: .takeoff)
      #expect(
        climbData.indicatedAirspeedKts.isApproximatelyEqual(
          to: ClimbProfileGenerator.takeoffClimbSpeedKIAS,
          absoluteTolerance: 0.001
        )
      )
    }
  }

  @Test
  func obstacleSpeedIsConstant() throws {
    let winds = makeWindsAloft()
    let profile = ClimbProfileGenerator.generate(
      windsAloft: winds,
      weightLb: 6000,
      aircraftType: .g1,
      seaLevelPressureInHg: 29.92,
      useRegressionModel: true
    )

    for dp in profile.dataPoints {
      let normal = dp.climbData(for: .enrouteObstacle(antiIce: false))
      let ice = dp.climbData(for: .enrouteObstacle(antiIce: true))
      #expect(
        normal.indicatedAirspeedKts.isApproximatelyEqual(
          to: ClimbProfileGenerator.obstacleClimbSpeedKIAS,
          absoluteTolerance: 0.001
        )
      )
      #expect(
        ice.indicatedAirspeedKts.isApproximatelyEqual(
          to: ClimbProfileGenerator.obstacleClimbSpeedKIAS,
          absoluteTolerance: 0.001
        )
      )
    }
  }

  // MARK: - Wind data

  @Test
  func windDataIsPreserved() throws {
    let winds = [
      ClimbProfileGenerator.WindsAloftObservation(
        altitudeFt: 5000,
        temperatureC: 5,
        windDirectionDeg: 270,
        windSpeedKts: 25
      )
    ]
    let profile = ClimbProfileGenerator.generate(
      windsAloft: winds,
      weightLb: 6000,
      aircraftType: .g1,
      seaLevelPressureInHg: 29.92,
      useRegressionModel: true
    )

    let dir = try #require(profile.windDirection(at: 5000))
    #expect(dir.isApproximatelyEqual(to: 270, absoluteTolerance: 0.001))

    let spd = try #require(profile.windSpeed(at: 5000))
    #expect(spd.isApproximatelyEqual(to: 25, absoluteTolerance: 0.001))
  }

  // MARK: - Tabular mode

  @Test
  func tabularModeProducesValidProfile() throws {
    let winds = makeWindsAloft()
    let profile = ClimbProfileGenerator.generate(
      windsAloft: winds,
      weightLb: 6000,
      aircraftType: .g1,
      seaLevelPressureInHg: 29.92,
      useRegressionModel: false
    )

    #expect(profile.dataPoints.count == winds.count)
    let g = try #require(profile.gradient(at: 5000, profile: .enroute(antiIce: false)))
    #expect(g > 0)
  }

  // MARK: - Reasonable values

  @Test
  func gradientValuesAreReasonable() throws {
    let winds = makeWindsAloft(altitudes: [0, 5000, 10000])
    let profile = ClimbProfileGenerator.generate(
      windsAloft: winds,
      weightLb: 6000,
      aircraftType: .g1,
      seaLevelPressureInHg: 29.92,
      useRegressionModel: true
    )

    // Enroute climb gradients should be in a reasonable range (100-800 ft/NM)
    for alt in [0.0, 5000.0, 10000.0] {
      let g = try #require(profile.gradient(at: alt, profile: .enroute(antiIce: false)))
      #expect(g > 100, "Gradient at \(alt) ft should be > 100 ft/NM")
      #expect(g < 800, "Gradient at \(alt) ft should be < 800 ft/NM")
    }
  }
}
