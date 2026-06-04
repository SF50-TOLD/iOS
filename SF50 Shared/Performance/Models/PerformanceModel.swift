/// Protocol defining aircraft performance calculation capabilities.
///
/// ``PerformanceModel`` abstracts the performance calculations for different
/// aircraft generations and calculation methods. Implementations include
/// tabular models (direct AFM table lookup) and regression models (curve-fitted
/// equations for smoother interpolation).
///
/// Performance models are configured with atmospheric conditions, aircraft
/// configuration, and runway data, then queried for specific performance values.
public protocol PerformanceModel {
  /// Takeoff climb gradient at Vx in feet per nautical mile.
  var takeoffClimbGradientFtNM: Value<Double> { get }

  /// Takeoff climb rate at Vx in feet per minute.
  var takeoffClimbRateFtMin: Value<Double> { get }

  /// Reference approach speed in knots.
  var VrefKts: Value<Double> { get }

  /// Whether the aircraft meets go-around climb gradient requirements.
  var meetsGoAroundClimbGradient: Value<Bool> { get }

  /// En route climb gradient in feet per nautical mile.
  var enrouteClimbGradientFtNM: Value<Double> { get }

  /// En route climb rate in feet per minute.
  var enrouteClimbRateFtMin: Value<Double> { get }

  /// En route climb speed in knots indicated airspeed.
  var enrouteClimbSpeedKIAS: Value<Double> { get }

  /// Whether takeoff inputs are below the minimum AFM table bounds.
  var takeoffInputsOffscaleLow: Bool { get }

  /// Whether takeoff inputs are above the maximum AFM table bounds.
  var takeoffInputsOffscaleHigh: Bool { get }

  /// Whether landing inputs are below the minimum AFM table bounds.
  var landingInputsOffscaleLow: Bool { get }

  /// Whether landing inputs are above the maximum AFM table bounds.
  var landingInputsOffscaleHigh: Bool { get }

  /// Computes the adjusted distance and breakdown for a given target.
  func computeDistance(for target: DistanceTarget)
    -> (value: Value<Double>, breakdown: DistanceBreakdown)
}
