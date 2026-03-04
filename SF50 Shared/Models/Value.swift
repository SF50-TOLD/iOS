import Foundation

/// A value that may be definite, uncertain, or in an error state.
///
/// ``Value`` is used throughout the SF50 TOLD app to represent calculated performance values
/// that may have uncertainty bounds or may be unavailable due to various conditions.
///
/// ## Overview
///
/// Performance calculations often produce results with uncertainty due to interpolation,
/// extrapolation, or measurement error. This type encapsulates both the value and its
/// uncertainty, while also representing error states like invalid inputs or offscale conditions.
public enum Value<T> {
  /// A definite value with no uncertainty.
  case value(T)

  /**
   * A value with an associated uncertainty range.
   *
   * The uncertainty represents one standard deviation (σ) from the central value.
   */
  case valueWithUncertainty(T, uncertainty: T)

  /// The value is invalid due to invalid input parameters.
  case invalid

  /// The value is not available for the given conditions.
  case notAvailable

  /// The calculation is not authorized (e.g., missing required data).
  case notAuthorized

  /// The required value exceeds the maximum valid range for the performance model.
  case offscaleHigh

  /// The required value is below the minimum valid range for the performance model.
  case offscaleLow

  /**
   * Transforms the value using the provided closure.
   *
   * - Parameter transform: A closure that transforms the wrapped value.
   * - Returns: A new ``Value`` with the transformed type.
   * - Note: This method cannot be called on ``valueWithUncertainty(_:uncertainty:)``.
   *   Use the two-parameter version instead.
   */
  public func map<U>(_ transform: (T) throws -> U) rethrows -> Value<U> {
    switch self {
      case .value(let v):
        try .value(transform(v))
      case .valueWithUncertainty:
        fatalError("Cannot call 1-arity .map on .valueWithUncertainty")
      case .invalid: .invalid
      case .notAvailable: .notAvailable
      case .notAuthorized: .notAuthorized
      case .offscaleHigh: .offscaleHigh
      case .offscaleLow: .offscaleLow
    }
  }

  /**
   * Transforms the value using a closure that returns a ``Value``.
   *
   * - Parameter transform: A closure that transforms the wrapped value into a new ``Value``.
   * - Returns: The result of applying the transform to the wrapped value.
   */
  public func flatMap<U>(_ transform: (T) throws -> Value<U>) rethrows -> Value<U> {
    switch self {
      case .value(let v):
        try transform(v)
      case .valueWithUncertainty(let v, _):
        try transform(v)
      case .invalid: .invalid
      case .notAvailable: .notAvailable
      case .notAuthorized: .notAuthorized
      case .offscaleHigh: .offscaleHigh
      case .offscaleLow: .offscaleLow
    }
  }

  /**
   * Transforms both the value and its uncertainty using the provided closure.
   *
   * - Parameter transform: A closure that transforms both the value and optional uncertainty.
   * - Returns: A new ``Value`` with the transformed type and uncertainty.
   */
  public func map<U>(_ transform: (T, T?) throws -> (U, U?)) rethrows -> Value<U> {
    switch self {
      case .value(let v):
        return try .value(transform(v, nil).0)
      case .valueWithUncertainty(let v, let uncertainty):
        let (tv, tu) = try transform(v, uncertainty)
        guard let tu else {
          fatalError("Must return uncertainty when calling .map with .valueWithUncertainty")
        }
        return .valueWithUncertainty(tv, uncertainty: tu)
      case .invalid: return .invalid
      case .notAvailable: return .notAvailable
      case .notAuthorized: return .notAuthorized
      case .offscaleHigh: return .offscaleHigh
      case .offscaleLow: return .offscaleLow
    }
  }
}

extension Value: Sendable where T: Sendable {}
extension Value: Equatable where T: Equatable {}

extension Value where T: FloatingPoint, T: Comparable {
  /// Multiplies two values, propagating uncertainty through quadrature.
  static func *= (lhs: inout Value<T>, rhs: Value<T>) {
    lhs =
      switch (lhs, rhs) {
        case (.value(let lv), .value(let rv)):
          .value(lv * rv)
        case (.value(let lv), .valueWithUncertainty(let rv, uncertainty: let ru)):
          .valueWithUncertainty(
            lv * rv,
            uncertainty: addUncertainties(leftValue: lv, rightUncertainty: ru)
          )
        case (.valueWithUncertainty(let lv, uncertainty: let lu), .value(let rv)):
          .valueWithUncertainty(
            lv * rv,
            uncertainty: addUncertainties(leftUncertainty: lu, rightValue: rv)
          )
        case (
          .valueWithUncertainty(let lv, uncertainty: let lu),
          .valueWithUncertainty(let rv, uncertainty: let ru)
        ):
          .valueWithUncertainty(
            lv * rv,
            uncertainty: addUncertainties(
              leftValue: lv,
              leftUncertainty: lu,
              rightValue: rv,
              rightUncertainty: ru
            )
          )
        case (.invalid, _), (_, .invalid): .invalid
        case (.notAuthorized, _), (_, .notAuthorized): .notAuthorized
        case (.notAvailable, _), (_, .notAvailable): .notAvailable
        case (.offscaleHigh, _), (_, .offscaleHigh): .offscaleHigh
        case (.offscaleLow, _), (_, .offscaleLow): .offscaleLow
      }
  }

  /// Multiplies a value by a scalar, scaling uncertainty proportionally.
  static func *= (lhs: inout Value<T>, rhs: T) {
    lhs = lhs.map { value, uncertainty in
      (value * rhs, uncertainty.map { $0 * abs(rhs) })
    }
  }

  /// Multiplies a value by a scalar, scaling uncertainty proportionally.
  static func * (lhs: Value<T>, rhs: T) -> Value<T> {
    lhs.map { value, uncertainty in
      (value * rhs, uncertainty.map { $0 * abs(rhs) })
    }
  }

  /// Adds two values, propagating uncertainty through quadrature (RSS).
  static func += (lhs: inout Value<T>, rhs: Value<T>) {
    lhs =
      switch (lhs, rhs) {
        case (.value(let lv), .value(let rv)):
          .value(lv + rv)
        case (.value(let lv), .valueWithUncertainty(let rv, uncertainty: let ru)):
          .valueWithUncertainty(lv + rv, uncertainty: ru)
        case (.valueWithUncertainty(let lv, uncertainty: let lu), .value(let rv)):
          .valueWithUncertainty(lv + rv, uncertainty: lu)
        case (
          .valueWithUncertainty(let lv, uncertainty: let lu),
          .valueWithUncertainty(let rv, uncertainty: let ru)
        ):
          .valueWithUncertainty(lv + rv, uncertainty: addUncertaintiesRSS(lu, ru))
        case (.invalid, _), (_, .invalid): .invalid
        case (.notAuthorized, _), (_, .notAuthorized): .notAuthorized
        case (.notAvailable, _), (_, .notAvailable): .notAvailable
        case (.offscaleHigh, _), (_, .offscaleHigh): .offscaleHigh
        case (.offscaleLow, _), (_, .offscaleLow): .offscaleLow
      }
  }

  /// Adds a scalar to a value, preserving uncertainty.
  static func += (lhs: inout Value<T>, rhs: T) {
    lhs = lhs.map { value, uncertainty in
      (value + rhs, uncertainty)
    }
  }

  /// Adds a value and a scalar, preserving uncertainty.
  static func + (lhs: Value<T>, rhs: T) -> Value<T> {
    lhs.map { value, uncertainty in
      (value + rhs, uncertainty)
    }
  }

  /// Subtracts two values, propagating uncertainty through quadrature (RSS).
  static func -= (lhs: inout Value<T>, rhs: Value<T>) {
    lhs =
      switch (lhs, rhs) {
        case (.value(let lv), .value(let rv)):
          .value(lv - rv)
        case (.value(let lv), .valueWithUncertainty(let rv, uncertainty: let ru)):
          .valueWithUncertainty(lv - rv, uncertainty: ru)
        case (.valueWithUncertainty(let lv, uncertainty: let lu), .value(let rv)):
          .valueWithUncertainty(lv - rv, uncertainty: lu)
        case (
          .valueWithUncertainty(let lv, uncertainty: let lu),
          .valueWithUncertainty(let rv, uncertainty: let ru)
        ):
          .valueWithUncertainty(lv - rv, uncertainty: addUncertaintiesRSS(lu, ru))
        case (.invalid, _), (_, .invalid): .invalid
        case (.notAuthorized, _), (_, .notAuthorized): .notAuthorized
        case (.notAvailable, _), (_, .notAvailable): .notAvailable
        case (.offscaleHigh, _), (_, .offscaleHigh): .offscaleHigh
        case (.offscaleLow, _), (_, .offscaleLow): .offscaleLow
      }
  }

  /// Subtracts a scalar from a value, preserving uncertainty.
  static func -= (lhs: inout Value<T>, rhs: T) {
    lhs = lhs.map { value, uncertainty in
      (value - rhs, uncertainty)
    }
  }

  /// Subtracts a scalar from a value, preserving uncertainty.
  static func - (lhs: Value<T>, rhs: T) -> Value<T> {
    lhs.map { value, uncertainty in
      (value - rhs, uncertainty)
    }
  }

  /// Subtracts two values, propagating uncertainty through quadrature (RSS).
  public static func - (lhs: Value<T>, rhs: Value<T>) -> Value<T> {
    var result = lhs
    result -= rhs
    return result
  }

  /// Adds two values, propagating uncertainty through quadrature (RSS).
  static func + (lhs: Value<T>, rhs: Value<T>) -> Value<T> {
    var result = lhs
    result += rhs
    return result
  }

  // MARK: - Uncertainty Helpers

  /// RSS (root sum of squares) combination for additive uncertainty propagation.
  private static func addUncertaintiesRSS(_ a: T, _ b: T) -> T {
    (a * a + b * b).squareRoot()
  }

  private static func addUncertainties(leftValue: T, rightUncertainty: T) -> T {
    abs(leftValue) * rightUncertainty
  }

  private static func addUncertainties(leftUncertainty: T, rightValue: T) -> T {
    abs(rightValue) * leftUncertainty
  }

  private static func addUncertainties(
    leftValue: T,
    leftUncertainty: T,
    rightValue: T,
    rightUncertainty: T
  ) -> T {
    // For multiplication, relative uncertainties add in quadrature
    // uncertainty = sqrt((lu/lv)^2 + (ru/rv)^2) * (lv * rv)
    let leftRelative = leftUncertainty / leftValue,
      rightRelative = rightUncertainty / rightValue,
      relativeUncertainty = (leftRelative * leftRelative + rightRelative * rightRelative)
        .squareRoot()
    return relativeUncertainty * leftValue * rightValue
  }
}

extension Value where T == Double {
  /// Converts a dimensionless double value to a `Measurement` value.
  public func toMeasurement<U: Dimension>(_ unit: U) -> Value<Measurement<U>> {
    self.map { value, uncertainty in
      (
        Measurement(value: value, unit: unit),
        uncertainty.map { Measurement(value: $0, unit: unit) }
      )
    }
  }
}

extension Value {

  /// The nominal value, ignoring uncertainty and error states.
  public var nominal: T? {
    switch self {
      case .value(let v), .valueWithUncertainty(let v, _): v
      default: nil
    }
  }
}

extension Value where T == Double {

  /// The nominal value, ignoring uncertainty and error states.
  @available(*, deprecated, renamed: "nominal")
  public var nominalValue: Double? { nominal }
}

extension Value where T == Double {

  /// Confidence level threshold for 1σ (68% of normal distribution).
  private static var oneSigmaConfidence: Double { 0.68 }

  /// Confidence level threshold for 2σ (95% of normal distribution).
  private static var twoSigmaConfidence: Double { 0.95 }

  /// z-score multiplier for 95% confidence interval.
  private static var zScore95: Double { 1.96 }

  /// z-score multiplier for 99% confidence interval.
  private static var zScore99: Double { 2.58 }

  /// Check if a value falls within the uncertainty bounds at the specified confidence level
  /// - Parameters:
  ///   - value: The value to test
  ///   - confidenceLevel: The confidence level (0.68 for 1σ, 0.95 for 2σ, etc.)
  /// - Returns: True if the value is within the confidence interval
  func contains(_ value: Double, confidenceLevel: Double = oneSigmaConfidence) -> Bool {
    switch self {
      case .value(let v):
        return value == v
      case .valueWithUncertainty(let centerValue, let uncertainty):
        let multiplier =
          if confidenceLevel <= Self.oneSigmaConfidence {
            uncertainty  // 1σ
          } else if confidenceLevel <= Self.twoSigmaConfidence {
            uncertainty * Self.zScore95
          } else {
            uncertainty * Self.zScore99
          }

        let lowerBound = centerValue - multiplier,
          upperBound = centerValue + multiplier
        return value >= lowerBound && value <= upperBound
      case .invalid: return false
      case .notAvailable: return false
      case .notAuthorized: return false
      case .offscaleHigh: return false
      case .offscaleLow: return false
    }
  }

  /// Legacy method for backward compatibility - uses 68% confidence level
  func contains(_ value: Double) -> Bool {
    return contains(value, confidenceLevel: Self.oneSigmaConfidence)
  }
}
