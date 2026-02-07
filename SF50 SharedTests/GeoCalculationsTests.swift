import Foundation
import RealModule
import Testing

@testable import SF50_Shared

struct GeoCalculationsTests {

  // MARK: - Wind Triangle

  @Test
  func windTriangleNoWind() {
    let result = GeoCalculations.windTriangle(
      trueHeading: .init(value: 90, unit: .degrees),
      tasKnots: 170,
      windFromTrue: .init(value: 0, unit: .degrees),
      windSpeedKnots: 0
    )
    #expect(
      result.groundTrack.converted(to: .degrees).value
        .isApproximatelyEqual(to: 90, absoluteTolerance: 0.01)
    )
    #expect(result.groundSpeedKnots.isApproximatelyEqual(to: 170, absoluteTolerance: 0.01))
  }

  @Test
  func windTriangleDirectHeadwind() {
    // Heading north, wind from north = headwind
    let result = GeoCalculations.windTriangle(
      trueHeading: .init(value: 0, unit: .degrees),
      tasKnots: 170,
      windFromTrue: .init(value: 0, unit: .degrees),
      windSpeedKnots: 30
    )
    // GS = TAS - wind = 140, track unchanged
    #expect(result.groundSpeedKnots.isApproximatelyEqual(to: 140, absoluteTolerance: 0.01))
    let track = result.groundTrack.converted(to: .degrees).value
    // Track should be 0 (or 360)
    let normalizedTrack = track < 1 ? track + 360 : track
    #expect(normalizedTrack.isApproximatelyEqual(to: 360, absoluteTolerance: 0.01))
  }

  @Test
  func windTriangleDirectTailwind() {
    // Heading north, wind from south = tailwind
    let result = GeoCalculations.windTriangle(
      trueHeading: .init(value: 0, unit: .degrees),
      tasKnots: 170,
      windFromTrue: .init(value: 180, unit: .degrees),
      windSpeedKnots: 30
    )
    // GS = TAS + wind = 200, track unchanged
    #expect(result.groundSpeedKnots.isApproximatelyEqual(to: 200, absoluteTolerance: 0.01))
    let track = result.groundTrack.converted(to: .degrees).value
    let normalizedTrack = track < 1 ? track + 360 : track
    #expect(normalizedTrack.isApproximatelyEqual(to: 360, absoluteTolerance: 0.01))
  }

  @Test
  func windTrianglePureCrosswind() {
    // Heading north, wind from west (270) = pushes east
    let result = GeoCalculations.windTriangle(
      trueHeading: .init(value: 0, unit: .degrees),
      tasKnots: 170,
      windFromTrue: .init(value: 270, unit: .degrees),
      windSpeedKnots: 30
    )
    // GS should be less than TAS+wind but more than TAS-wind
    // sqrt(170^2 + 30^2) = sqrt(29800) ~ 172.6
    let expectedGS = (170.0 * 170.0 + 30.0 * 30.0).squareRoot()
    #expect(result.groundSpeedKnots.isApproximatelyEqual(to: expectedGS, absoluteTolerance: 0.1))

    // Track should be deflected east of north
    let track = result.groundTrack.converted(to: .degrees).value
    #expect(track > 0 && track < 90)

    // Expected track: atan2(30, 170) in degrees ~ 10.0°
    let expectedTrack = atan2(30.0, 170.0) * 180 / .pi
    #expect(track.isApproximatelyEqual(to: expectedTrack, absoluteTolerance: 0.1))
  }
}
