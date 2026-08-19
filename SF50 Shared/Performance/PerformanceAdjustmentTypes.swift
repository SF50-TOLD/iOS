import Defaults
import Foundation
import MeasurementKit
import SwiftUI

/// Which distance is being computed.
public enum DistanceTarget: Sendable {
  case takeoffRun
  case takeoffDistance
  case landingRun
  case landingDistance

  public var isLanding: Bool { self == .landingRun || self == .landingDistance }
  public var isGroundRun: Bool { self == .takeoffRun || self == .landingRun }
  public var isTotalDistance: Bool { self == .takeoffDistance || self == .landingDistance }
}

/// Identifies a specific adjustment applied to a performance distance.
public enum AdjustmentKind: Sendable {
  case headwind(Measurement<UnitSpeed>)
  case tailwind(Measurement<UnitSpeed>)
  case uphillGradient(Float)
  case downhillGradient(Float)
  case unpavedSurface
  case contamination(Contamination)
  case safetyMargin(Double)
  case VREFAdditive(Measurement<UnitSpeed>)

  /// Localized description of the adjustment for display to the user.
  public var localizedDescription: String {
    switch self {
      case .headwind(let speed):
        return String(localized: "Headwind — \(speed.asSpeed, format: .speed)")
      case .tailwind(let speed):
        return String(localized: "Tailwind — \(speed.asSpeed, format: .speed)")
      case .uphillGradient(let gradient):
        return String(
          localized: "Uphill — \(gradient, format: .percent.precision(.fractionLength(0...2)))"
        )
      case .downhillGradient(let gradient):
        return String(
          localized: "Downhill — \(gradient, format: .percent.precision(.fractionLength(0...2)))"
        )
      case .unpavedSurface:
        return String(localized: "Unpaved Surface")
      case .contamination:
        return String(localized: "Contamination")
      case .safetyMargin(let factor):
        return String(
          localized: "Safety Factor — \(factor, format: .number.precision(.fractionLength(2)))"
        )
      case .VREFAdditive(let speed):
        return String(localized: "VREF — \(speed.asSpeed, format: .speed(plusSign: true))")
    }
  }

  /// Localized attributed description with subscripted VREF where applicable.
  public var localizedAttributedDescription: AttributedString {
    switch self {
      case .VREFAdditive(let speed):
        .VREF
          + AttributedString(
            localized: " — \(speed.asSpeed, format: .speed(plusSign: true))"
          )
      default:
        AttributedString(localizedDescription)
    }
  }
}

/// A single adjustment applied to a distance.
public struct PerformanceAdjustment: Sendable {
  public let kind: AdjustmentKind

  /// The effective multiplier for this adjustment (e.g., 0.944 for a 5.6% headwind reduction).
  public let multiplier: Double

  /// The running total distance in feet after this adjustment is applied.
  public let resultFt: Value<Double>

  public init(kind: AdjustmentKind, multiplier: Double, resultFt: Value<Double>) {
    self.kind = kind
    self.multiplier = multiplier
    self.resultFt = resultFt
  }
}

/// Base value plus ordered adjustments for a single distance.
public struct DistanceBreakdown: Sendable {

  /// The base distance in feet before any adjustments.
  public let baseFt: Value<Double>

  /// The ordered list of adjustments applied to the base distance.
  public let adjustments: [PerformanceAdjustment]

  public init(baseFt: Value<Double>, adjustments: [PerformanceAdjustment]) {
    self.baseFt = baseFt
    self.adjustments = adjustments
  }

  /// Returns a new breakdown with additional adjustments appended.
  func appending(_ additional: [PerformanceAdjustment]) -> Self {
    Self(baseFt: baseFt, adjustments: adjustments + additional)
  }
}

/// Severity level for a performance note.
public enum PerformanceNoteSeverity: Int, Sendable, Comparable {
  case warning = 0
  case info = 1

  public static func < (lhs: Self, rhs: Self) -> Bool {
    lhs.rawValue < rhs.rawValue
  }
}

/// A warning or note about the performance calculation.
public enum PerformanceNote: Sendable {
  // Offscale
  case offscaleHigh
  case offscaleLow

  // Informational
  case contaminationSupplemental
  case rwyCCSafetyFactorNotApplied
  case VREFAdditiveApproximate

  // Exceedances (warnings)
  case crosswindExceedance(crosswind: Measurement<UnitSpeed>, limit: Measurement<UnitSpeed>)
  case tailwindExceedance(tailwind: Measurement<UnitSpeed>, limit: Measurement<UnitSpeed>)
  case weightAboveMax(weight: Measurement<UnitMass>, limit: Measurement<UnitMass>)
  case zeroFuelWeightExceeded(weight: Measurement<UnitMass>, limit: Measurement<UnitMass>)
  case fuelExceedsCapacity(fuel: Measurement<UnitVolume>, limit: Measurement<UnitVolume>)
  case takeoffDistanceExceedsAvailable(
    required: Measurement<UnitLength>,
    available: Measurement<UnitLength>
  )
  case takeoffRunExceedsAvailable(
    required: Measurement<UnitLength>,
    available: Measurement<UnitLength>
  )
  case landingDistanceExceedsAvailable(
    required: Measurement<UnitLength>,
    available: Measurement<UnitLength>
  )
  case insufficientClimbGradient(
    required: Measurement<UnitSlope>,
    actual: Value<Measurement<UnitSlope>>
  )
  case doesNotMeetGoAroundGradient

  public var severity: PerformanceNoteSeverity {
    switch self {
      case .offscaleHigh:
        .warning
      case .offscaleLow,
        .contaminationSupplemental,
        .rwyCCSafetyFactorNotApplied,
        .VREFAdditiveApproximate:
        .info
      case .crosswindExceedance, .tailwindExceedance,
        .weightAboveMax, .zeroFuelWeightExceeded, .fuelExceedsCapacity,
        .takeoffDistanceExceedsAvailable,
        .takeoffRunExceedsAvailable,
        .landingDistanceExceedsAvailable,
        .insufficientClimbGradient,
        .doesNotMeetGoAroundGradient:
        .warning
    }
  }

  /// Localized description of the note for display to the user.
  public var localizedDescription: String {
    switch self {
      case .offscaleHigh:
        return String(
          localized:
            "The input values are above the maximums specified in the AFM table. Proceed with extreme caution."
        )
      case .offscaleLow:
        return String(
          localized: "The input values are below the minimums specified in the AFM table."
        )
      case .contaminationSupplemental:
        return String(
          localized:
            "Contaminated runway performance data is considered supplemental and is not FAA approved."
        )
      case .rwyCCSafetyFactorNotApplied:
        return String(
          localized:
            "AC 91-79B landing distance factors are applied. The configured safety factor is not applied to RwyCC landing distances."
        )
      case .VREFAdditiveApproximate:
        return String(
          localized:
            "Landing distances include an AC 91-79B §5.2.2 adjustment for the VREF additive. This is an approximation."
        )
      case .crosswindExceedance(let crosswind, let limit):
        return String(
          localized:
            "Crosswind of \(crosswind.asSpeed, format: .speed) exceeds the \(limit.asSpeed, format: .speed) limit."
        )
      case .tailwindExceedance(let tailwind, let limit):
        return String(
          localized:
            "Tailwind of \(tailwind.asSpeed, format: .speed) exceeds the \(limit.asSpeed, format: .speed) limit."
        )
      case .weightAboveMax(let weight, let limit):
        return String(
          localized:
            "Weight of \(weight.asWeight, format: .weight) exceeds the \(limit.asWeight, format: .weight) maximum."
        )
      case .zeroFuelWeightExceeded(let weight, let limit):
        return String(
          localized:
            "Zero-fuel weight of \(weight.asWeight, format: .weight) exceeds the \(limit.asWeight, format: .weight) maximum."
        )
      case .fuelExceedsCapacity(let fuel, let limit):
        return String(
          localized:
            "Fuel quantity of \(fuel.asFuel, format: .fuel) exceeds the \(limit.asFuel, format: .fuel) usable capacity."
        )
      case .takeoffDistanceExceedsAvailable(let required, let available):
        return String(
          localized:
            "Takeoff distance of \(required.asLength, format: .length) exceeds the available \(available.asLength, format: .length)."
        )
      case .takeoffRunExceedsAvailable(let required, let available):
        return String(
          localized:
            "Takeoff run of \(required.asLength, format: .length) exceeds the available \(available.asLength, format: .length)."
        )
      case .landingDistanceExceedsAvailable(let required, let available):
        return String(
          localized:
            "Landing distance of \(required.asLength, format: .length) exceeds the available \(available.asLength, format: .length)."
        )
      case .insufficientClimbGradient:
        return String(localized: "Required climb gradient may exceed actual climb performance.")
      case .doesNotMeetGoAroundGradient:
        return String(localized: "Go-around climb gradient requirement is not met.")
    }
  }
}
