import Defaults
import MeasurementKit
import SF50_Shared
import SwiftUI

/// The visual half of ``RunwayNumbersIntent``.
///
/// A distance spoken aloud with nothing beside it is exactly the untraceable number this app exists to
/// avoid, so every figure here appears next to the runway it applies to, the distance available, the
/// wind that shaped it, and the observation it came from.
struct RunwayNumbersSnippet: View {
  var airportDisplayID: String
  var runway: RunwaySnapshot
  var operation: SF50_Shared.Operation
  var flapSetting: FlapSetting
  var performance: RunwayPerformance?
  var conditions: Conditions

  @Default(.runwayLengthUnit)
  private var runwayLengthUnit

  @Default(.speedUnit)
  private var speedUnit

  private var availableDistance: Measurement<UnitLength> {
    runway.availableDistance(for: operation)
  }

  /// The ground run has to fit the run available, which is a shorter figure than the distance
  /// available wherever a runway has a clearway.
  private var availableRun: Measurement<UnitLength> {
    runway.availableRun(for: operation)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      header
      Divider()
      numbers
      Divider()
      footer
    }
    .padding()
  }

  private var header: some View {
    HStack(alignment: .firstTextBaseline) {
      Text("\(airportDisplayID) \(runway.name)")
        .font(.headline)
      Spacer()
      WindComponents(runway: runway, conditions: conditions)
    }
  }

  @ViewBuilder private var numbers: some View {
    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
      if operation == .landing, let VREF = performance?.VREF {
        SnippetRow(label: Text("VREF"), value: VREF) {
          Text($0.converted(to: speedUnit), format: .speed)
        }
      }

      SnippetRow(
        label: Text("Ground Run"),
        value: performance?.groundRun ?? .notAvailable,
        maximum: availableRun,
        available: Text("of \(availableRun.converted(to: runwayLengthUnit), format: .length)")
      ) {
        Text($0.converted(to: runwayLengthUnit), format: .length)
      }

      SnippetRow(
        label: Text("Total Distance"),
        value: performance?.distance ?? .notAvailable,
        maximum: availableDistance,
        available: Text("of \(availableDistance.converted(to: runwayLengthUnit), format: .length)")
      ) {
        Text($0.converted(to: runwayLengthUnit), format: .length)
      }

      if let climbGradient = performance?.climbGradient {
        SnippetRow(label: Text("Vx Climb Gradient"), value: climbGradient) {
          Text($0.converted(to: .feetPerNauticalMile), format: .gradient)
        }
      }
    }
  }

  private var footer: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(configurationSummary)
      Text(
        "\(conditions.source.providers.localizedDescription) · \(conditions.validTime.start, format: .dateTime.hour().minute())"
      )
    }
    .font(.caption)
    .foregroundStyle(.secondary)
  }

  private var configurationSummary: String {
    switch operation {
      case .takeoff: String(localized: "Takeoff · \(format(flapSetting: .flaps50))")
      case .landing: String(localized: "Landing · \(format(flapSetting: flapSetting))")
    }
  }
}

/// One labelled number, rendered through ``InterpolationView`` so a refusal keeps its own wording.
private struct SnippetRow<UnitType: Dimension, Content: View>: View {
  private let label: Text
  private let value: Value<Measurement<UnitType>>
  private let maximum: Measurement<UnitType>?
  private let available: Text?
  private let content: (Measurement<UnitType>) -> Content

  var body: some View {
    GridRow {
      label.foregroundStyle(.secondary)
      HStack(spacing: 4) {
        InterpolationView(value: value, maximum: maximum, displayValue: content)
        available?.foregroundStyle(.secondary)
      }
    }
  }

  init(
    label: Text,
    value: Value<Measurement<UnitType>>,
    maximum: Measurement<UnitType>? = nil,
    available: Text? = nil,
    @ViewBuilder content: @escaping (Measurement<UnitType>) -> Content
  ) {
    self.label = label
    self.value = value
    self.maximum = maximum
    self.available = available
    self.content = content
  }
}

#Preview("Takeoff") {
  PreviewView(insert: .KSQL) { preview in
    let runway = try preview.load(airportID: "SQL", runway: "30")!

    return RunwayNumbersSnippet(
      airportDisplayID: "SQL",
      runway: .init(from: runway),
      operation: .takeoff,
      flapSetting: .flaps50,
      performance: .init(
        groundRun: .value(.init(value: 2100, unit: .feet)),
        distance: .value(.init(value: 2800, unit: .feet)),
        climbGradient: .value(.init(value: 500, unit: UnitSlope.feetPerNauticalMile))
      ),
      conditions: preview.lightWinds
    )
  }
}

#Preview("Landing") {
  PreviewView(insert: .KSQL) { preview in
    let runway = try preview.load(airportID: "SQL", runway: "30")!

    return RunwayNumbersSnippet(
      airportDisplayID: "SQL",
      runway: .init(from: runway),
      operation: .landing,
      flapSetting: .flaps100,
      performance: .init(
        groundRun: .value(.init(value: 1700, unit: .feet)),
        distance: .value(.init(value: 2400, unit: .feet)),
        VREF: .value(.init(value: 88, unit: .knots))
      ),
      conditions: preview.lightWinds
    )
  }
}

#Preview("Refused") {
  PreviewView(insert: .KSQL) { preview in
    let runway = try preview.load(airportID: "SQL", runway: "30")!

    return RunwayNumbersSnippet(
      airportDisplayID: "SQL",
      runway: .init(from: runway),
      operation: .takeoff,
      flapSetting: .flaps50,
      performance: .init(groundRun: .offscaleHigh, distance: .offscaleHigh),
      conditions: preview.veryHot
    )
  }
}
