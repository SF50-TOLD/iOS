public import Foundation
import MeasurementKit

/// A runway direction that wind can be resolved against.
///
/// Both the SwiftData ``Runway`` model and the `Sendable` ``RunwaySnapshot`` carry a true heading, and
/// both need the same head/crosswind decomposition. Conforming to ``RunwayOrientation`` gives them one
/// implementation instead of two copies that can drift apart.
public protocol RunwayOrientation {
  /// Runway heading in degrees true.
  var trueHeading: Measurement<UnitAngle> { get }
}

extension RunwayOrientation {
  /// The wind component along the runway centerline.
  ///
  /// Positive is a headwind and negative a tailwind. Variable winds report no direction, so they
  /// resolve to zero rather than crediting a component the observation does not support.
  ///
  /// - Parameter conditions: The weather conditions to resolve.
  /// - Returns: The headwind component, or zero when the wind has no direction or speed.
  public func headwind(conditions: Conditions) -> Measurement<UnitSpeed> {
    guard let windDirection = conditions.windDirection,
      let windSpeed = conditions.windSpeed
    else { return .zero }
    return windSpeed * cos(windDirection - trueHeading)
  }

  /// The wind component across the runway centerline.
  ///
  /// Positive is a crosswind from the right and negative from the left.
  ///
  /// - Parameter conditions: The weather conditions to resolve.
  /// - Returns: The crosswind component, or zero when the wind has no direction or speed.
  public func crosswind(conditions: Conditions) -> Measurement<UnitSpeed> {
    guard let windDirection = conditions.windDirection,
      let windSpeed = conditions.windSpeed
    else { return .zero }
    return windSpeed * sin(windDirection - trueHeading)
  }
}
