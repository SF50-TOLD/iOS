import Foundation
import RealModule
import Testing

@testable import SF50_Shared

struct MeasurementArithmeticTests {

  /// Adding in place has to convert, not demand that both sides already agree.
  ///
  /// Foundation supplies two `+` operators: the one on `Measurement` where
  /// `UnitType: Dimension` converts, and the one on a plain `Unit` traps on any
  /// mismatch. A sum seeded with ``Measurement/zero`` is stated in base units,
  /// so adding a quantity expressed in any other unit — the runway map's
  /// chevron spacing in feet, say — is the shape that reaches the trapping one.
  @Test
  func addingInPlaceConvertsMismatchedUnits() {
    var distance = Measurement<UnitLength>.zero
    distance += .init(value: 60, unit: .feet)
    distance += .init(value: 1, unit: .meters)

    #expect(
      distance.converted(to: .meters).value
        .isApproximatelyEqual(to: 19.288, absoluteTolerance: 1e-6)
    )
  }
}
