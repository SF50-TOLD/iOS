import Foundation
import RealModule
import Testing

@testable import SF50_Shared

struct MeasurementAngleTests {

  /// True runway headings from nav data, with O22's 16°E variation, must yield the
  /// published magnetic headings on the Jeppesen chart (Rwy 35→354, 17→174, 11→118, 29→298).
  @Test
  func `to magnetic applies east variation`() {
    let variation = Measurement(value: 16, unit: UnitAngle.degrees)
    let cases: [(trueDeg: Double, magneticDeg: Double)] = [
      (10, 354), (190, 174), (134, 118), (314, 298)
    ]

    for (trueDeg, magneticDeg) in cases {
      let result = Measurement(value: trueDeg, unit: UnitAngle.degrees)
        .toMagnetic(variation: variation)
      #expect(
        result.converted(to: .degrees).value
          .isApproximatelyEqual(to: magneticDeg, absoluteTolerance: 1e-6)
      )
    }
  }
}
