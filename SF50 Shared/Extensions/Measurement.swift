import Foundation

extension Measurement where UnitType: Dimension {
  /// The zero measurement, for comparing against a signed quantity or seeding a sum.
  public static var zero: Self { .init(value: 0, unit: .baseUnit()) }

  /// Adds `rhs` to `lhs`, converting between the two units.
  ///
  /// The `UnitType: Dimension` bound is what makes this convert. Foundation
  /// declares `+` twice: the dimensional one converts both sides to base units,
  /// while the one on a plain `Unit` traps on any mismatch. An unconstrained
  /// extension only ever sees the trapping overload, so a sum seeded with
  /// ``zero`` — stated in base units — would abort the moment it was given a
  /// quantity in any other unit.
  public static func += (lhs: inout Self, rhs: Self) {
    lhs = lhs + rhs
  }
}

extension Measurement {
  public var absoluteValue: Self {
    .init(value: abs(value), unit: unit)
  }

  public var magnitude: Self { .init(value: value.magnitude, unit: unit) }

  public static prefix func - (val: Self) -> Self {
    .init(value: -val.value, unit: val.unit)
  }

  public static func / <U: Dimension>(lhs: Measurement<U>, rhs: Measurement<U>) -> Double {
    lhs.converted(to: .baseUnit()).value / rhs.converted(to: .baseUnit()).value
  }

  public static func * (lhs: Measurement<UnitVolume>, rhs: Measurement<UnitDensity>) -> Measurement<
    UnitMass
  > {
    let value = lhs.converted(to: .baseUnit()).value * rhs.converted(to: .baseUnit()).value
    return .init(value: value, unit: .baseUnit())
  }
}

extension UnitSpeed {
  public static let feetPerMinute = UnitSpeed(
    symbol: "ft/min",
    converter: UnitConverterLinear(coefficient: 0.00508)
  )
}

public func sin(_ angle: Measurement<UnitAngle>) -> Double {
  sin(angle.converted(to: .radians).value)
}

public func cos(_ angle: Measurement<UnitAngle>) -> Double {
  cos(angle.converted(to: .radians).value)
}

public func tan(_ angle: Measurement<UnitAngle>) -> Double {
  tan(angle.converted(to: .radians).value)
}

extension Measurement where UnitType == UnitTemperature {
  /// This temperature shifted by a deviation from it.
  ///
  /// A deviation is a difference rather than a reading, and the two do not add: measurements sum in
  /// the base unit, so a 15 °C standard temperature plus a 10 °C deviation would come out near
  /// 300 °C. The deviation is read as its Celsius offset instead, which is how one is stored — a
  /// deviation set in degrees keeps that many degrees through any absolute scale it is carried on.
  ///
  /// - Parameter deviation: How far from this temperature the result stands.
  /// - Returns: The shifted temperature.
  public func deviated(by deviation: Self) -> Self {
    .init(
      value: converted(to: .celsius).value + deviation.converted(to: .celsius).value,
      unit: .celsius
    )
  }
}

extension Measurement where UnitType == UnitAngle {
  public var reciprocal: Self {
    let degreesValue = self.converted(to: .degrees).value
    let reciprocalDegrees = (degreesValue + 180).truncatingRemainder(dividingBy: 360)
    return .init(value: reciprocalDegrees, unit: .degrees)
  }

  /// Converts a magnetic bearing to true bearing using the given variation.
  public func toTrue(variation: Measurement<UnitAngle>) -> Measurement<UnitAngle> {
    let trueDeg =
      (converted(to: .degrees).value
      + variation.converted(to: .degrees).value)
      .truncatingRemainder(dividingBy: 360)
    return .init(value: trueDeg < 0 ? trueDeg + 360 : trueDeg, unit: .degrees)
  }

  /// Converts a true bearing to magnetic bearing using the given variation.
  public func toMagnetic(variation: Measurement<UnitAngle>) -> Measurement<UnitAngle> {
    let magneticDeg =
      (converted(to: .degrees).value
      - variation.converted(to: .degrees).value)
      .truncatingRemainder(dividingBy: 360)
    return .init(value: magneticDeg < 0 ? magneticDeg + 360 : magneticDeg, unit: .degrees)
  }
}
