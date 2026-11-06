import Defaults
public import Foundation
public import MeasurementKit

// MARK: - Unit Conversion Extensions

/// Convenience extension methods for converting measurements to user-preferred units.
///
/// These extensions provide semantic unit conversion methods that respect user preferences
/// stored in Defaults. Each method returns the measurement converted to the appropriate
/// unit based on user settings.
extension Measurement where UnitType == UnitLength {
  /// Converts to the user's preferred height unit.
  ///
  /// Settings keeps separate preferences for runway lengths and heights: a runway is measured
  /// along the ground and an altitude above it, and a pilot reading runway lengths in feet may
  /// still want altitudes in metres.
  public var asHeight: Self { converted(to: Defaults[.heightUnit]) }
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

extension DisplayUnits {
  /// The units the pilot has chosen in Settings.
  public static var preferred: Self {
    .init(
      weight: Defaults[.weightUnit],
      fuel: Defaults[.fuelVolumeUnit],
      length: Defaults[.runwayLengthUnit],
      height: Defaults[.heightUnit],
      speed: Defaults[.speedUnit],
      temperature: Defaults[.temperatureUnit]
    )
  }
}
