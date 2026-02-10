import Foundation
import RealModule
import Testing

@testable import SF50_Shared

struct ClimbProfileTests {

  // MARK: - Helpers

  /// Default profile type used by most tests.
  private let defaultProfile: ClimbProfile.ProfileType = .enroute(antiIce: false)

  /// Creates a uniform ClimbData with the given gradient and 170 KIAS.
  private func uniformClimbData(gradientFtPerNM: Double) -> ClimbProfile.ClimbData {
    .init(gradientFtPerNM: gradientFtPerNM, indicatedAirspeedKts: 170)
  }

  /// Creates a simple profile with given gradient, ISA temps, zero wind, 170 KIAS.
  private func makeProfile(
    gradientFtPerNM: Double,
    altitudes: [Double] = [0, 5000, 10000],
    windDirectionDeg: Double = 0,
    windSpeedKts: Double = 0,
    seaLevelPressureInHg: Double = 29.92
  ) -> ClimbProfile {
    let dataPoints = altitudes.map { alt in
      let cd = uniformClimbData(gradientFtPerNM: gradientFtPerNM)
      return ClimbProfile.DataPoint(
        altitudeFt: alt,
        outsideAirTemperatureC: 15.0 - alt * 0.00198,
        windDirectionDeg: windDirectionDeg,
        windSpeedKts: windSpeedKts,
        takeoff: cd,
        enrouteObstacle: cd,
        enrouteObstacleAntiIce: cd,
        enroute: cd,
        enrouteAntiIce: cd
      )
    }
    return ClimbProfile(dataPoints: dataPoints, seaLevelPressureInHg: seaLevelPressureInHg)
  }

  /// Creates a profile with varying gradients at specific altitudes.
  private func makeVaryingProfile(
    _ pairs: [(altitudeFt: Double, gradientFtPerNM: Double)]
  ) -> ClimbProfile {
    let dataPoints = pairs.map { pair in
      let cd = uniformClimbData(gradientFtPerNM: pair.gradientFtPerNM)
      return ClimbProfile.DataPoint(
        altitudeFt: pair.altitudeFt,
        outsideAirTemperatureC: 15.0 - pair.altitudeFt * 0.00198,
        windDirectionDeg: 0,
        windSpeedKts: 0,
        takeoff: cd,
        enrouteObstacle: cd,
        enrouteObstacleAntiIce: cd,
        enroute: cd,
        enrouteAntiIce: cd
      )
    }
    return ClimbProfile(dataPoints: dataPoints, seaLevelPressureInHg: 29.92)
  }

  // MARK: - gradient(at:profile:)

  @Test
  func gradientAtExactDataPoint() throws {
    let profile = makeVaryingProfile([
      (altitudeFt: 0, gradientFtPerNM: 400),
      (altitudeFt: 5000, gradientFtPerNM: 300),
      (altitudeFt: 10000, gradientFtPerNM: 200)
    ])
    let g = try #require(profile.gradient(at: 5000, profile: defaultProfile))
    #expect(g.isApproximatelyEqual(to: 300, absoluteTolerance: 0.001))
  }

  @Test
  func gradientInterpolatesBetweenPoints() throws {
    let profile = makeVaryingProfile([
      (altitudeFt: 0, gradientFtPerNM: 400),
      (altitudeFt: 10000, gradientFtPerNM: 200)
    ])
    // Midpoint should be 300
    let g = try #require(profile.gradient(at: 5000, profile: defaultProfile))
    #expect(g.isApproximatelyEqual(to: 300, absoluteTolerance: 0.001))
  }

  @Test
  func gradientClampsBelowRange() throws {
    let profile = makeVaryingProfile([
      (altitudeFt: 1000, gradientFtPerNM: 350),
      (altitudeFt: 10000, gradientFtPerNM: 200)
    ])
    let g = try #require(profile.gradient(at: 0, profile: defaultProfile))
    #expect(g.isApproximatelyEqual(to: 350, absoluteTolerance: 0.001))
  }

  @Test
  func gradientClampsAboveRange() throws {
    let profile = makeVaryingProfile([
      (altitudeFt: 0, gradientFtPerNM: 400),
      (altitudeFt: 10000, gradientFtPerNM: 200)
    ])
    let g = try #require(profile.gradient(at: 15000, profile: defaultProfile))
    #expect(g.isApproximatelyEqual(to: 200, absoluteTolerance: 0.001))
  }

  @Test
  func gradientEmptyDataPoints() {
    let profile = ClimbProfile(dataPoints: [], seaLevelPressureInHg: 29.92)
    #expect(profile.gradient(at: 5000, profile: defaultProfile) == nil)
  }

  @Test
  func gradientSingleDataPoint() throws {
    let profile = makeVaryingProfile([
      (altitudeFt: 5000, gradientFtPerNM: 300)
    ])
    // Single data point: below range clamp
    let gLow = try #require(profile.gradient(at: 0, profile: defaultProfile))
    #expect(gLow.isApproximatelyEqual(to: 300, absoluteTolerance: 0.001))
    // Above range clamp
    let gHigh = try #require(profile.gradient(at: 10000, profile: defaultProfile))
    #expect(gHigh.isApproximatelyEqual(to: 300, absoluteTolerance: 0.001))
  }

  @Test
  func initSortsDataPoints() {
    let profile = makeVaryingProfile([
      (altitudeFt: 10000, gradientFtPerNM: 200),
      (altitudeFt: 0, gradientFtPerNM: 400),
      (altitudeFt: 5000, gradientFtPerNM: 300)
    ])
    #expect(profile.dataPoints[0].altitudeFt == 0)
    #expect(profile.dataPoints[1].altitudeFt == 5000)
    #expect(profile.dataPoints[2].altitudeFt == 10000)
  }

  // MARK: - altitude(after:from:profile:)

  @Test
  func altitudeConstantGradient() throws {
    // 300 ft/NM constant; after 10 NM from 1000 ft => 1000 + 3000 = 4000
    let profile = Helper.createTestClimbProfile(gradientFtPerNM: 300)
    let alt = try #require(profile.altitude(after: 10, from: 1000, profile: defaultProfile))
    #expect(alt.isApproximatelyEqual(to: 4000, absoluteTolerance: 5))
  }

  @Test
  func altitudeVaryingGradient() throws {
    // Gradient decreases with altitude: should gain less than linear extrapolation
    let profile = makeVaryingProfile([
      (altitudeFt: 0, gradientFtPerNM: 400),
      (altitudeFt: 10000, gradientFtPerNM: 100)
    ])
    let alt = try #require(profile.altitude(after: 10, from: 0, profile: defaultProfile))
    // Linear at 400 ft/NM would give 4000; with decreasing gradient should be less
    #expect(alt < 4000)
    #expect(alt > 1000)
  }

  @Test
  func altitudeZeroDistance() throws {
    let profile = Helper.createTestClimbProfile()
    let alt = try #require(profile.altitude(after: 0, from: 5000, profile: defaultProfile))
    #expect(alt.isApproximatelyEqual(to: 5000, absoluteTolerance: 0.001))
  }

  @Test
  func altitudeNegativeDistance() {
    let profile = Helper.createTestClimbProfile()
    #expect(profile.altitude(after: -1, from: 5000, profile: defaultProfile) == nil)
  }

  @Test
  func altitudeEmptyProfile() {
    let profile = ClimbProfile(dataPoints: [], seaLevelPressureInHg: 29.92)
    #expect(profile.altitude(after: 10, from: 5000, profile: defaultProfile) == nil)
  }

  // MARK: - distance(from:to:profile:)

  @Test
  func distanceConstantGradient() throws {
    // 300 ft/NM; climbing 3000 ft requires 10 NM
    let profile = Helper.createTestClimbProfile(gradientFtPerNM: 300)
    let dist = try #require(profile.distance(from: 1000, to: 4000, profile: defaultProfile))
    #expect(dist.isApproximatelyEqual(to: 10, absoluteTolerance: 0.5))
  }

  @Test
  func distanceStartEqualsEnd() {
    let profile = Helper.createTestClimbProfile()
    #expect(profile.distance(from: 5000, to: 5000, profile: defaultProfile) == nil)
  }

  @Test
  func distanceStartAboveEnd() {
    let profile = Helper.createTestClimbProfile()
    #expect(profile.distance(from: 5000, to: 3000, profile: defaultProfile) == nil)
  }

  @Test
  func distanceRoundTripsWithAltitude() throws {
    let profile = Helper.createTestClimbProfile(gradientFtPerNM: 300)
    let startAlt = 2000.0
    let endAlt = 5000.0
    let dist = try #require(profile.distance(from: startAlt, to: endAlt, profile: defaultProfile))
    let recoveredAlt = try #require(
      profile.altitude(after: dist, from: startAlt, profile: defaultProfile)
    )
    #expect(recoveredAlt.isApproximatelyEqual(to: endAlt, absoluteTolerance: 10))
  }

  // MARK: - TAS computation

  @Test
  func trueAirspeedAtSeaLevelISA() throws {
    // At sea level ISA (15C, 29.92 inHg), TAS ~= IAS
    let profile = makeProfile(gradientFtPerNM: 300, altitudes: [0])
    let tas = try #require(profile.trueAirspeed(at: 0, profile: defaultProfile))
    // Should be very close to 170 KIAS at sea level standard conditions
    #expect(tas.isApproximatelyEqual(to: 170, absoluteTolerance: 2))
  }

  @Test
  func trueAirspeedIncreasesWithAltitude() throws {
    // TAS should be greater than IAS at altitude (lower density)
    let profile = makeProfile(gradientFtPerNM: 300, altitudes: [0, 10000])
    let tasLow = try #require(profile.trueAirspeed(at: 0, profile: defaultProfile))
    let tasHigh = try #require(profile.trueAirspeed(at: 10000, profile: defaultProfile))
    #expect(tasHigh > tasLow)
    // At 10,000 ft ISA, TAS should be roughly 15-20% more than IAS
    #expect(tasHigh > 170 * 1.10)
    #expect(tasHigh < 170 * 1.30)
  }

  @Test
  func trueAirspeedInterpolation() throws {
    // TAS at midpoint should be between endpoints
    let profile = makeProfile(gradientFtPerNM: 300, altitudes: [0, 10000])
    let tasLow = try #require(profile.trueAirspeed(at: 0, profile: defaultProfile))
    let tasMid = try #require(profile.trueAirspeed(at: 5000, profile: defaultProfile))
    let tasHigh = try #require(profile.trueAirspeed(at: 10000, profile: defaultProfile))
    #expect(tasMid > tasLow)
    #expect(tasMid < tasHigh)
  }

  // MARK: - Wind interpolation

  @Test
  func windDirectionInterpolation() throws {
    let cd = uniformClimbData(gradientFtPerNM: 300)
    let dp1 = ClimbProfile.DataPoint(
      altitudeFt: 0,
      outsideAirTemperatureC: 15,
      windDirectionDeg: 180,
      windSpeedKts: 10,
      takeoff: cd,
      enrouteObstacle: cd,
      enrouteObstacleAntiIce: cd,
      enroute: cd,
      enrouteAntiIce: cd
    )
    let dp2 = ClimbProfile.DataPoint(
      altitudeFt: 10000,
      outsideAirTemperatureC: 5,
      windDirectionDeg: 270,
      windSpeedKts: 30,
      takeoff: cd,
      enrouteObstacle: cd,
      enrouteObstacleAntiIce: cd,
      enroute: cd,
      enrouteAntiIce: cd
    )
    let profile = ClimbProfile(dataPoints: [dp1, dp2], seaLevelPressureInHg: 29.92)

    let dir = try #require(profile.windDirection(at: 5000))
    #expect(dir.isApproximatelyEqual(to: 225, absoluteTolerance: 0.1))

    let spd = try #require(profile.windSpeed(at: 5000))
    #expect(spd.isApproximatelyEqual(to: 20, absoluteTolerance: 0.1))
  }

  @Test
  func windSpeedClampsOutsideRange() throws {
    let cd = uniformClimbData(gradientFtPerNM: 300)
    let dp = ClimbProfile.DataPoint(
      altitudeFt: 5000,
      outsideAirTemperatureC: 5,
      windDirectionDeg: 270,
      windSpeedKts: 25,
      takeoff: cd,
      enrouteObstacle: cd,
      enrouteObstacleAntiIce: cd,
      enroute: cd,
      enrouteAntiIce: cd
    )
    let profile = ClimbProfile(dataPoints: [dp], seaLevelPressureInHg: 29.92)

    let spdBelow = try #require(profile.windSpeed(at: 0))
    #expect(spdBelow.isApproximatelyEqual(to: 25, absoluteTolerance: 0.1))

    let spdAbove = try #require(profile.windSpeed(at: 10000))
    #expect(spdAbove.isApproximatelyEqual(to: 25, absoluteTolerance: 0.1))
  }

  // MARK: - Profile type selection

  @Test
  func differentProfileTypesReturnDifferentGradients() throws {
    // Create a profile where takeoff and enroute have different gradients
    let altitudes: [Double] = [0, 5000, 10000]
    let dataPoints = altitudes.map { alt in
      ClimbProfile.DataPoint(
        altitudeFt: alt,
        outsideAirTemperatureC: 15.0 - alt * 0.00198,
        windDirectionDeg: 0,
        windSpeedKts: 0,
        takeoff: .init(gradientFtPerNM: 500, indicatedAirspeedKts: 91),
        enrouteObstacle: .init(gradientFtPerNM: 400, indicatedAirspeedKts: 120),
        enrouteObstacleAntiIce: .init(gradientFtPerNM: 350, indicatedAirspeedKts: 120),
        enroute: .init(gradientFtPerNM: 300, indicatedAirspeedKts: 170),
        enrouteAntiIce: .init(gradientFtPerNM: 250, indicatedAirspeedKts: 160)
      )
    }
    let profile = ClimbProfile(dataPoints: dataPoints, seaLevelPressureInHg: 29.92)

    let takeoffGrad = try #require(profile.gradient(at: 5000, profile: .takeoff))
    let obstacleGrad = try #require(
      profile.gradient(at: 5000, profile: .enrouteObstacle(antiIce: false))
    )
    let obstacleIceGrad = try #require(
      profile.gradient(at: 5000, profile: .enrouteObstacle(antiIce: true))
    )
    let enrouteGrad = try #require(profile.gradient(at: 5000, profile: .enroute(antiIce: false)))
    let enrouteIceGrad = try #require(profile.gradient(at: 5000, profile: .enroute(antiIce: true)))

    #expect(takeoffGrad.isApproximatelyEqual(to: 500, absoluteTolerance: 0.001))
    #expect(obstacleGrad.isApproximatelyEqual(to: 400, absoluteTolerance: 0.001))
    #expect(obstacleIceGrad.isApproximatelyEqual(to: 350, absoluteTolerance: 0.001))
    #expect(enrouteGrad.isApproximatelyEqual(to: 300, absoluteTolerance: 0.001))
    #expect(enrouteIceGrad.isApproximatelyEqual(to: 250, absoluteTolerance: 0.001))
  }
}
