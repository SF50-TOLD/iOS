import Defaults
import MeasurementKit
public import SwiftUI

/// A view displaying headwind and crosswind components with visual indicators.
///
/// ``WindComponents`` shows wind components relative to a runway with:
/// - **Headwind**: Green down-arrow, reduces takeoff/landing distance
/// - **Tailwind**: Red up-arrow, increases distance
/// - **Left crosswind**: Gray left-arrow
/// - **Right crosswind**: Gray right-arrow
///
/// ## Limit Validation
///
/// When `tailwindLimit` or `crosswindLimit` is specified, the value turns red
/// if limits are exceeded.
///
/// ## Usage
///
/// ```swift
/// WindComponents(
///     runway: selectedRunway,
///     conditions: currentConditions,
///     crosswindLimit: Measurement(value: 18, unit: .knots),
///     tailwindLimit: Measurement(value: 10, unit: .knots)
/// )
/// ```
public struct WindComponents: View {
  var headwind: Measurement<UnitSpeed>
  var crosswind: Measurement<UnitSpeed>
  var crosswindLimit: Measurement<UnitSpeed>?
  var tailwindLimit: Measurement<UnitSpeed>?

  @Default(.speedUnit)
  private var speedUnit

  private var exceedsTailwindLimits: Bool {
    guard let tailwindLimit else { return false }
    return headwind < -tailwindLimit
  }

  private var exceedsCrosswindLimits: Bool {
    guard let crosswindLimit else { return false }
    return crosswind.magnitude > crosswindLimit
  }

  public var body: some View {
    HStack {
      if headwind.isPositive {
        HStack(spacing: 0) {
          Image(systemName: "arrowtriangle.down.fill")
            .foregroundStyle(.green)
            .accessibilityLabel("headwind")
          Text(headwind.converted(to: speedUnit).value.magnitude, format: .speed)
            .contentTransition(.numericText())
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(.primary)
            .accessibilityIdentifier("headwind")
        }
      } else if headwind.isNegative {
        HStack(spacing: 0) {
          Image(systemName: "arrowtriangle.up.fill")
            .foregroundStyle(.red)
            .accessibilityLabel("tailwind")
          Text(headwind.converted(to: speedUnit).value.magnitude, format: .speed)
            .contentTransition(.numericText())
            .foregroundStyle(exceedsTailwindLimits ? .red : .primary)
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityIdentifier("headwind")
        }
      }
      if crosswind.isPositive {
        HStack(spacing: 0) {
          Image(systemName: "arrowtriangle.left.fill")
            .foregroundStyle(.gray)
            .accessibilityLabel("left crosswind")
          Text(crosswind.converted(to: speedUnit).value.magnitude, format: .speed)
            .contentTransition(.numericText())
            .foregroundStyle(exceedsCrosswindLimits ? .red : .primary)
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityIdentifier("crosswind")
        }
      } else if crosswind.isNegative {
        HStack(spacing: 0) {
          Image(systemName: "arrowtriangle.right.fill")
            .foregroundStyle(.gray)
            .accessibilityLabel("right crosswind")
          Text(crosswind.converted(to: speedUnit).value.magnitude, format: .speed)
            .contentTransition(.numericText())
            .foregroundStyle(exceedsCrosswindLimits ? .red : .primary)
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityIdentifier("crosswind")
        }
      }
    }
    .animation(.default, value: headwind)
    .animation(.default, value: crosswind)
  }

  /// Creates a view from already-resolved wind components.
  ///
  /// - Parameters:
  ///   - headwind: Headwind component; negative values are a tailwind.
  ///   - crosswind: Crosswind component.
  ///   - crosswindLimit: Turns the crosswind red when exceeded.
  ///   - tailwindLimit: Turns the tailwind red when exceeded.
  public init(
    headwind: Measurement<UnitSpeed>,
    crosswind: Measurement<UnitSpeed>,
    crosswindLimit: Measurement<UnitSpeed>? = nil,
    tailwindLimit: Measurement<UnitSpeed>? = nil
  ) {
    self.headwind = headwind
    self.crosswind = crosswind
    self.crosswindLimit = crosswindLimit
    self.tailwindLimit = tailwindLimit
  }

  /// Creates a view by resolving the wind against a runway.
  ///
  /// - Parameters:
  ///   - runway: The runway to resolve the wind against.
  ///   - conditions: The weather conditions supplying the wind.
  ///   - crosswindLimit: Turns the crosswind red when exceeded.
  ///   - tailwindLimit: Turns the tailwind red when exceeded.
  public init(
    runway: some RunwayOrientation,
    conditions: Conditions,
    crosswindLimit: Measurement<UnitSpeed>? = nil,
    tailwindLimit: Measurement<UnitSpeed>? = nil
  ) {
    self.init(
      headwind: runway.headwind(conditions: conditions),
      crosswind: runway.crosswind(conditions: conditions),
      crosswindLimit: crosswindLimit,
      tailwindLimit: tailwindLimit
    )
  }
}

extension Measurement where UnitType == UnitSpeed {
  fileprivate var isPositive: Bool { asSpeed.value.rounded() >= 1 }
  fileprivate var isNegative: Bool { asSpeed.value.rounded() <= -1 }
}

#Preview {
  PreviewView(insert: .KOAK) { preview in
    let runway = AirportBuilder.KSQL.unsaved().runways[0]

    return List {
      LabeledContent("ISA") {
        WindComponents(runway: runway, conditions: preview.ISA)
      }
      LabeledContent("Headwind") {
        WindComponents(runway: runway, conditions: preview.lightWinds)
      }
      LabeledContent("Tailwind") {
        WindComponents(
          runway: runway,
          conditions: preview.strongWinds,
          crosswindLimit: .init(value: 18, unit: .knots),
          tailwindLimit: .init(value: 10, unit: .knots)
        )
      }
    }
  }
}
