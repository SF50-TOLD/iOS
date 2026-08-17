import Foundation
import RealModule
import Testing

@testable import SF50_Shared

struct GeoCalculationsTests {

  // MARK: - Wind Triangle

  @Test
  func windTriangleNoWind() {
    let result = GeoCalculations.windTriangle(
      trueHeadingDeg: 90,
      TAS_Kts: 170,
      windFromTrueDeg: 0,
      windSpeedKts: 0
    )
    #expect(result.groundTrackDeg.isApproximatelyEqual(to: 90, absoluteTolerance: 0.01))
    #expect(result.groundSpeedKts.isApproximatelyEqual(to: 170, absoluteTolerance: 0.01))
  }

  @Test
  func windTriangleDirectHeadwind() {
    // Heading north, wind from north = headwind
    let result = GeoCalculations.windTriangle(
      trueHeadingDeg: 0,
      TAS_Kts: 170,
      windFromTrueDeg: 0,
      windSpeedKts: 30
    )
    // GS = TAS - wind = 140, track unchanged
    #expect(result.groundSpeedKts.isApproximatelyEqual(to: 140, absoluteTolerance: 0.01))
    let track = result.groundTrackDeg
    // Track should be 0 (or 360)
    let normalizedTrack = track < 1 ? track + 360 : track
    #expect(normalizedTrack.isApproximatelyEqual(to: 360, absoluteTolerance: 0.01))
  }

  @Test
  func windTriangleDirectTailwind() {
    // Heading north, wind from south = tailwind
    let result = GeoCalculations.windTriangle(
      trueHeadingDeg: 0,
      TAS_Kts: 170,
      windFromTrueDeg: 180,
      windSpeedKts: 30
    )
    // GS = TAS + wind = 200, track unchanged
    #expect(result.groundSpeedKts.isApproximatelyEqual(to: 200, absoluteTolerance: 0.01))
    let track = result.groundTrackDeg
    let normalizedTrack = track < 1 ? track + 360 : track
    #expect(normalizedTrack.isApproximatelyEqual(to: 360, absoluteTolerance: 0.01))
  }

  @Test
  func windTrianglePureCrosswind() {
    // Heading north, wind from west (270) = pushes east
    let result = GeoCalculations.windTriangle(
      trueHeadingDeg: 0,
      TAS_Kts: 170,
      windFromTrueDeg: 270,
      windSpeedKts: 30
    )
    // GS should be less than TAS+wind but more than TAS-wind
    // sqrt(170^2 + 30^2) = sqrt(29800) ~ 172.6
    let expectedGS = (170.0 * 170.0 + 30.0 * 30.0).squareRoot()
    #expect(result.groundSpeedKts.isApproximatelyEqual(to: expectedGS, absoluteTolerance: 0.1))

    // Track should be deflected east of north
    let track = result.groundTrackDeg
    #expect(track > 0 && track < 90)

    // Expected track: atan2(30, 170) in degrees ~ 10.0°
    let expectedTrack = atan2(30.0, 170.0) * 180 / .pi
    #expect(track.isApproximatelyEqual(to: expectedTrack, absoluteTolerance: 0.1))
  }
}
