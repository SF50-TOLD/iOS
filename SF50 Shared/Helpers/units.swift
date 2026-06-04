import Defaults
import Foundation

// MARK: - Unit Conversion Extensions

/// Convenience extension methods for converting measurements to user-preferred units.
///
/// These extensions provide semantic unit conversion methods that respect user preferences
/// stored in Defaults. Each method returns the measurement converted to the appropriate
/// unit based on user settings.
extension Measurement where UnitType == UnitMass {
  /// Converts to user's preferred weight unit.
  public var asWeight: Self { converted(to: Defaults[.weightUnit]) }
}

extension Measurement where UnitType == UnitVolume {
  public var asFuel: Self { converted(to: Defaults[.fuelVolumeUnit]) }
}

extension Measurement where UnitType == UnitLength {
  public var asLength: Self { converted(to: Defaults[.runwayLengthUnit]) }
}

extension Measurement where UnitType == UnitSpeed {
  public var asSpeed: Self { converted(to: Defaults[.speedUnit]) }
}

extension Measurement where UnitType == UnitAngle {
  // Heading always uses degrees regardless of user preference
  public var asHeading: Self { converted(to: .degrees) }
}

extension Measurement where UnitType == UnitSlope {
  public var asGradient: Self { converted(to: .feetPerNauticalMile) }
}
