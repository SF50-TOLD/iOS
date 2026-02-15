import Foundation

/// Altitude restriction for a fix in a departure procedure.
///
/// ``AltitudeRestriction`` represents the altitude constraints that must be met
/// at a specific fix during a departure procedure. Restrictions can specify
/// exact altitudes, minimums, maximums, or ranges.
///
/// This type follows the same serialization pattern as ``Contamination`` -
/// it is stored as separate fields in the parent model rather than as a
/// `@Model` itself.
public enum AltitudeRestriction: Sendable, Hashable {
  /// Must cross at exactly this altitude
  case at(Measurement<UnitLength>)

  /// Must cross at or above this altitude
  case atOrAbove(Measurement<UnitLength>)

  /// Must cross at or below this altitude
  case atOrBelow(Measurement<UnitLength>)

  /// Must cross between minimum and maximum altitudes
  case between(min: Measurement<UnitLength>, max: Measurement<UnitLength>)

  /// Raw type string for persistence.
  var type: String {
    switch self {
      case .at: RestrictionType.at.rawValue
      case .atOrAbove: RestrictionType.atOrAbove.rawValue
      case .atOrBelow: RestrictionType.atOrBelow.rawValue
      case .between: RestrictionType.between.rawValue
    }
  }

  /// Minimum altitude value in meters for persistence.
  var altitudeMin: Double? {
    switch self {
      case .at(let altitude): altitude.converted(to: .meters).value
      case .atOrAbove(let altitude): altitude.converted(to: .meters).value
      case .atOrBelow(let altitude): altitude.converted(to: .meters).value
      case .between(let min, _): min.converted(to: .meters).value
    }
  }

  /// Maximum altitude value in meters for persistence (only used for between).
  var altitudeMax: Double? {
    switch self {
      case .at: nil
      case .atOrAbove: nil
      case .atOrBelow: nil
      case .between(_, let max): max.converted(to: .meters).value
    }
  }

  /// Human-readable description of the altitude restriction.
  public var description: String {
    let formatter = MeasurementFormatter()
    formatter.unitOptions = .providedUnit
    formatter.numberFormatter.maximumFractionDigits = 0

    switch self {
      case .at(let altitude):
        let feet = altitude.converted(to: .feet)
        return "At \(formatter.string(from: feet))"
      case .atOrAbove(let altitude):
        let feet = altitude.converted(to: .feet)
        return "At or above \(formatter.string(from: feet))"
      case .atOrBelow(let altitude):
        let feet = altitude.converted(to: .feet)
        return "At or below \(formatter.string(from: feet))"
      case .between(let min, let max):
        let minFeet = min.converted(to: .feet)
        let maxFeet = max.converted(to: .feet)
        return "Between \(formatter.string(from: minFeet)) and \(formatter.string(from: maxFeet))"
    }
  }

  /// Creates altitude restriction from persistence storage values.
  init?(type: String?, altitudeMin: Double?, altitudeMax: Double?) {
    guard let type, let typeEnum = RestrictionType(rawValue: type) else { return nil }

    switch typeEnum {
      case .at:
        guard let altitudeMin else { return nil }
        self = .at(.init(value: altitudeMin, unit: .meters))
      case .atOrAbove:
        guard let altitudeMin else { return nil }
        self = .atOrAbove(.init(value: altitudeMin, unit: .meters))
      case .atOrBelow:
        guard let altitudeMin else { return nil }
        self = .atOrBelow(.init(value: altitudeMin, unit: .meters))
      case .between:
        guard let altitudeMin, let altitudeMax else { return nil }
        self = .between(
          min: .init(value: altitudeMin, unit: .meters),
          max: .init(value: altitudeMax, unit: .meters)
        )
    }
  }

  /// Raw string values for persistence.
  enum RestrictionType: String {
    case at
    case atOrAbove
    case atOrBelow
    case between
  }
}

extension AltitudeRestriction {
  /// Whether this restriction can serve as a climb target altitude.
  ///
  /// `atOrBelow` restrictions define a ceiling, not a climb target.
  var isClimbTarget: Bool {
    switch self {
      case .at, .atOrAbove, .between: true
      case .atOrBelow: false
    }
  }

  /// Creates from Codable representation (values in feet).
  public init(from codable: AirportDataCodable.AltitudeRestrictionCodable) {
    switch codable {
      case .at(let feet):
        self = .at(.init(value: Double(feet), unit: .feet))
      case .atOrAbove(let feet):
        self = .atOrAbove(.init(value: Double(feet), unit: .feet))
      case .atOrBelow(let feet):
        self = .atOrBelow(.init(value: Double(feet), unit: .feet))
      case .between(let minFeet, let maxFeet):
        self = .between(
          min: .init(value: Double(minFeet), unit: .feet),
          max: .init(value: Double(maxFeet), unit: .feet)
        )
    }
  }

  func isViolated(byAltitudeFt altitudeFt: Double) -> Bool {
    switch self {
      case .atOrAbove(let altitude):
        altitudeFt < altitude.converted(to: .feet).value
      case .atOrBelow(let altitude):
        altitudeFt > altitude.converted(to: .feet).value
      case .at(let altitude):
        abs(altitudeFt - altitude.converted(to: .feet).value) > 100
      case .between(let minAlt, let maxAlt):
        altitudeFt < minAlt.converted(to: .feet).value
          || altitudeFt > maxAlt.converted(to: .feet).value
    }
  }
}
