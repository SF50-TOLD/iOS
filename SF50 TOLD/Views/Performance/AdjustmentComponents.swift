import Defaults
import MeasurementKit
import SF50_Shared
import SwiftUI

// MARK: - Breakdown Section

struct BreakdownSection: View {
  let title: String
  let breakdown: DistanceBreakdown
  let total: Value<Measurement<UnitLength>>
  var maximum: Measurement<UnitLength>?

  @Default(.runwayLengthUnit)
  private var runwayLengthUnit

  var body: some View {
    Section(title) {
      LabeledContent("Base Distance") {
        InterpolationView(value: breakdown.baseFt.toMeasurement(UnitLength.feet)) { distance in
          Text(distance.converted(to: runwayLengthUnit), format: .length)
            .foregroundStyle(.secondary)
        } displayUncertainty: { uncertainty in
          Text("±\(uncertainty.converted(to: runwayLengthUnit), format: .length)")
        }
      }

      ForEach(Array(adjustmentDisplays.enumerated()), id: \.offset) { _, display in
        AdjustmentRow(display: display)
      }

      LabeledContent(title) {
        InterpolationView(value: total, maximum: maximum) { distance in
          Text(distance.converted(to: runwayLengthUnit), format: .length)
            .bold()
        } displayUncertainty: { uncertainty in
          Text("±\(uncertainty.converted(to: runwayLengthUnit), format: .length)")
        }
      }
    }
  }

  private var adjustmentDisplays: [AdjustmentDisplay] {
    var previousResultFt = breakdown.baseFt
    return breakdown.adjustments.map { adjustment in
      let deltaValueFt: Value<Double> = adjustment.resultFt - previousResultFt
      let deltaFt = deltaValueFt.toMeasurement(UnitLength.feet)
      previousResultFt = adjustment.resultFt
      return AdjustmentDisplay(
        description: adjustment.kind.localizedAttributedDescription,
        deltaFt: deltaFt,
        isWarning: adjustment.multiplier > 1.01
      )
    }
  }
}

// MARK: - Adjustment Row

struct AdjustmentDisplay {
  let description: AttributedString
  let deltaFt: Value<Measurement<UnitLength>>
  let isWarning: Bool
}

private struct AdjustmentRow: View {
  let display: AdjustmentDisplay

  @Default(.runwayLengthUnit)
  private var runwayLengthUnit

  var body: some View {
    LabeledContent {
      InterpolationView(value: display.deltaFt) { delta in
        Text(
          "\(delta.converted(to: runwayLengthUnit), format: .length(plusSign: true))"
        )
      } displayUncertainty: { uncertainty in
        Text("±\(uncertainty.converted(to: runwayLengthUnit), format: .length)")
      }
    } label: {
      Text(display.description)
    }
  }
}

// MARK: - Notes Section

struct NotesSection: View {
  let notes: [PerformanceNote]

  var body: some View {
    Section("Notes") {
      ForEach(Array(sortedNotes.enumerated()), id: \.offset) { _, note in
        NoteRow(note: note)
      }
    }
  }

  private var sortedNotes: [PerformanceNote] {
    notes.sorted { $0.severity < $1.severity }
  }
}

private struct NoteRow: View {
  let note: PerformanceNote

  var body: some View {
    HStack(alignment: .top, spacing: 8) {
      Image(systemName: note.severity == .warning ? "exclamationmark.triangle" : "info.circle")
        .accessibilityLabel(note.severity == .warning ? "Warning" : "Info")
        .foregroundStyle(note.severity == .warning ? .red : .secondary)
      Text(note.localizedDescription)
        .foregroundStyle(note.severity == .warning ? .red : .secondary)
    }
    .font(.subheadline)
  }
}

// MARK: - Previews

#Preview {
  let sampleBreakdown = DistanceBreakdown(
    baseFt: .value(1850),
    adjustments: [
      .init(
        kind: .headwind(.init(value: 8, unit: .knots)),
        multiplier: 0.944,
        resultFt: .value(1850 * 0.944)
      ),
      .init(
        kind: .uphillGradient(0.02),
        multiplier: 1.07,
        resultFt: .value(1850 * 0.944 * 1.07)
      ),
      .init(
        kind: .safetyMargin(1.67),
        multiplier: 1.67,
        resultFt: .value(1850 * 0.944 * 1.07 * 1.67)
      )
    ]
  )

  let sampleWarningNotes: [PerformanceNote] = [
    .takeoffDistanceExceedsAvailable(
      required: .init(value: 5319, unit: .feet),
      available: .init(value: 5000, unit: .feet)
    ),
    .insufficientClimbGradient(
      required: .init(value: 200, unit: .feetPerNauticalMile),
      actual: .value(.init(value: 180, unit: .feetPerNauticalMile))
    )
  ]

  let sampleInfoNotes: [PerformanceNote] = [
    .rwyCCSafetyFactorNotApplied,
    .contaminationSupplemental
  ]

  return List {
    BreakdownSection(
      title: String(localized: "Ground Run"),
      breakdown: sampleBreakdown,
      total: .value(.init(value: 2850, unit: .feet))
    )
    NotesSection(notes: sampleWarningNotes + sampleInfoNotes)
  }
}
