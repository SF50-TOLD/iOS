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
  /// Atmospheric conditions for the calculation.
  var conditions: Conditions { get }

  /// Aircraft weight and flap configuration.
  var configuration: Configuration { get }

  /// Runway physical properties and declared distances.
  var runway: RunwayInput { get }

  /// Active NOTAM restrictions (contamination, obstacles, etc.).
  var notam: NOTAMInput? { get }

  /// Takeoff ground run distance in feet.
  var takeoffRunFt: Value<Double> { get }

  /// Takeoff distance to 35 feet AGL in feet.
  var takeoffDistanceFt: Value<Double> { get }

  /// Takeoff climb gradient at Vx in feet per nautical mile.
  var takeoffClimbGradientFtNM: Value<Double> { get }

  /// Takeoff climb rate at Vx in feet per minute.
  var takeoffClimbRateFtMin: Value<Double> { get }

  /// Reference approach speed in knots.
  var VrefKts: Value<Double> { get }

  /// Landing ground run distance in feet.
  var landingRunFt: Value<Double> { get }

  /// Landing distance from 50 feet AGL in feet.
  var landingDistanceFt: Value<Double> { get }

  /// Whether the aircraft meets go-around climb gradient requirements.
  var meetsGoAroundClimbGradient: Value<Bool> { get }

  /// En route climb gradient in feet per nautical mile.
  var enrouteClimbGradientFtNM: Value<Double> { get }

  /// En route climb rate in feet per minute.
  var enrouteClimbRateFtMin: Value<Double> { get }

  /// En route climb speed in knots indicated airspeed.
  var enrouteClimbSpeedKIAS: Value<Double> { get }

  /// En route obstacle climb gradient in feet per nautical mile.
  var enrouteObstacleClimbGradientFtNM: Value<Double> { get }

  /// En route obstacle climb rate in feet per minute.
  var enrouteObstacleClimbRateFtMin: Value<Double> { get }

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
