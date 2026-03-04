import Foundation

/// Performance adjustment factor calculations.
///
/// ``PerformanceAdjustments`` provides generic formulas to calculate multiplicative
/// adjustment factors for wind, gradient, and surface conditions. These factors
/// are applied to base performance values to account for environmental effects.
///
/// ## Sign Convention
///
/// Callers pass signed values so that a positive effect increases distance:
/// - **Wind**: pass negative for headwind (reduces distance), positive for tailwind
/// - **Gradient**: pass positive to increase distance, negative to decrease
///   (takeoff: uphill positive, downhill negative; landing: reversed)
///
/// ## Two Overloads
///
/// Each formula has a scalar overload (for regression models) and a `Value<Double>`
/// overload (for tabular models where the factor comes from a ``DataTable`` lookup).
enum PerformanceAdjustments {

  // MARK: - Scalar Formulas

  /// Wind adjustment multiplier.
  ///
  /// - Parameters:
  ///   - factor: The per-10-knot adjustment factor (always positive).
  ///   - wind: Signed wind value (negative = headwind, positive = tailwind).
  static func windAdjustment(factor: Double, wind: Double) -> Double {
    1 + factor * wind / 10
  }

  /// Gradient adjustment multiplier.
  ///
  /// - Parameters:
  ///   - factor: The per-percent adjustment factor (always positive).
  ///   - gradient: Signed gradient value (positive = increases distance).
  static func gradientAdjustment(factor: Double, gradient: Double) -> Double {
    1 + factor * gradient * 100
  }

  /// Surface adjustment multiplier for unpaved runways.
  static func surfaceAdjustment(factor: Double) -> Double {
    1 + factor
  }

  // MARK: - Tabular Formulas

  /// Wind adjustment multiplier from a table-derived factor.
  static func windAdjustment(factor: Value<Double>, wind: Double) -> Value<Double> {
    factor.map { 1 + $0 * wind / 10 }
  }

  /// Gradient adjustment multiplier from a table-derived factor.
  static func gradientAdjustment(factor: Value<Double>, gradient: Double) -> Value<Double> {
    factor.map { 1 + $0 * gradient * 100 }
  }

  /// Surface adjustment multiplier from a table-derived factor.
  static func surfaceAdjustment(factor: Value<Double>) -> Value<Double> {
    factor.map { 1 + $0 }
  }
}
