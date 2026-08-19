import Foundation
import MeasurementKit

extension Measurement {
  /// The mass of a volume of fluid at a given density.
  ///
  /// Kept local rather than taken from MeasurementKit because ``UnitDensity`` is persisted in
  /// `Defaults` and so stays a SF50 type; the package's operator is typed on the package's unit.
  ///
  /// - Parameters:
  ///   - lhs: The volume.
  ///   - rhs: The density it is filled with.
  /// - Returns: The mass, in kilograms.
  public static func * (lhs: Measurement<UnitVolume>, rhs: Measurement<UnitDensity>) -> Measurement<
    UnitMass
  > {
    let value = lhs.converted(to: .baseUnit()).value * rhs.converted(to: .baseUnit()).value
    return .init(value: value, unit: .baseUnit())
  }
}

extension Measurement where UnitType == UnitAngle {
  /// Converts a magnetic bearing to true bearing using the given variation.
  public func toTrue(variation: Measurement<UnitAngle>) -> Measurement<UnitAngle> {
    rotated(by: variation)
  }

  /// Converts a true bearing to magnetic bearing using the given variation.
  public func toMagnetic(variation: Measurement<UnitAngle>) -> Measurement<UnitAngle> {
    rotated(by: -variation)
  }
}
