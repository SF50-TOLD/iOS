import Defaults
import SF50_Shared
import SwiftUI

private enum ContaminationType {
  case none
  case waterOrSlush
  case slushOrWetSnow
  case drySnow
  case compactSnow
  case wetRunway
  case rwyCC

  var hasDepth: Bool {
    self == .waterOrSlush || self == .slushOrWetSnow
  }

  init(from contamination: Contamination?) {
    switch contamination {
      case .waterOrSlush: self = .waterOrSlush
      case .slushOrWetSnow: self = .slushOrWetSnow
      case .drySnow: self = .drySnow
      case .compactSnow: self = .compactSnow
      case .wetRunway: self = .wetRunway
      case .rwyCC: self = .rwyCC
      case .none: self = .none
    }
  }
}

struct ContaminationView: View {
  /// The depths the slider offers, and the one it starts at.
  ///
  /// The range is the AFM’s own applicability for contaminated-runway data — “greater than 0.1
  /// inch (3.0 mm) of contaminant” — out to the deepest depth it tabulates, so a pilot can enter
  /// whatever the field is reporting. Its tables start an eighth of an inch deep, which no tenth
  /// reaches, so the shallowest stop lies outside them and the tabular model reports it offscale
  /// rather than answering for it. The control opens a stop deeper instead: the shallowest
  /// stop the tables do cover, and, since they lengthen the ground run further the shallower the
  /// contaminant, the most penalizing depth the slider can reach and still be answered.
  private static let minDepth = Measurement(value: 0.1, unit: UnitLength.inches),
    maxDepth = Contamination.deepestTabulatedDepth.converted(to: .inches),
    defaultDepth = Measurement(value: 0.2, unit: UnitLength.inches)

  /// A tenth of an inch, the increment a contaminant depth is written to — so every stop the
  /// slider offers reads back exactly as the depth the models are asked for.
  private static let depthStepInches = 0.1

  @Binding var contamination: Contamination?

  @State private var contaminationType = ContaminationType.none
  @State private var contaminationDepth = Self.defaultDepth.value
  @State private var rwyCC: UInt8 = 6

  private var contaminationDepthMeasurement: Measurement<UnitLength> {
    .init(value: contaminationDepth, unit: .inches)
  }

  var body: some View {
    Section("Contamination") {
      HStack {
        Text("Contamination")
        Picker("", selection: $contaminationType) {
          Text("None").tag(ContaminationType.none)
          Text("Wet Runway").tag(ContaminationType.wetRunway)
          Text("Water/Slush").tag(ContaminationType.waterOrSlush)
          Text("Slush/Wet Snow").tag(ContaminationType.slushOrWetSnow)
          Text("Dry Snow").tag(ContaminationType.drySnow)
          Text("Compact Snow").tag(ContaminationType.compactSnow)
          Text("RwyCC").tag(ContaminationType.rwyCC)
        }.accessibilityIdentifier("contaminationTypePicker")
      }

      if contaminationType.hasDepth {
        VStack {
          LabeledContent("Depth") {
            Text(contaminationDepthMeasurement, format: .depth)
          }

          HStack {
            Text(Self.minDepth, format: .depth)
              .foregroundStyle(.secondary)
            Slider(
              value: $contaminationDepth,
              in: Self.minDepth.value...Self.maxDepth.value,
              step: Self.depthStepInches
            )
            .accessibilityIdentifier("contaminationDepthSlider")
            Text(Self.maxDepth, format: .depth)
              .foregroundStyle(.secondary)
          }
        }
      }

      if contaminationType == .rwyCC {
        VStack {
          LabeledContent("RwyCC") {
            Text("\(rwyCC, format: .number)")
          }

          HStack {
            Text("1")
              .foregroundStyle(.secondary)
            Slider(
              value: Binding(
                get: { Double(rwyCC) },
                set: { rwyCC = max(1, min(6, UInt8($0))) }
              ),
              in: 1...6,
              step: 1
            )
            .accessibilityIdentifier("rwyCCSlider")
            Text("6")
              .foregroundStyle(.secondary)
          }
        }

        RwyCCWarningView()
      }
    }
    .onAppear {
      contaminationType = .init(from: contamination)
      contaminationDepth = contamination?.depthInches ?? Self.defaultDepth.value
      if case .rwyCC(let code) = contamination {
        rwyCC = code
      }
    }
    .onChange(of: contaminationType) {
      contamination = makeContamination()
    }
    .onChange(of: contaminationDepth) {
      contamination = makeContamination()
    }
    .onChange(of: rwyCC) {
      contamination = makeContamination()
    }
  }

  private func makeContamination() -> Contamination? {
    switch contaminationType {
      case .none: return nil
      case .waterOrSlush:
        return .waterOrSlush(depth: .init(value: contaminationDepth, unit: .inches))
      case .slushOrWetSnow:
        return .slushOrWetSnow(
          depth: .init(value: contaminationDepth, unit: .inches)
        )
      case .drySnow: return .drySnow
      case .compactSnow: return .compactSnow
      case .wetRunway: return .wetRunway
      case .rwyCC: return .rwyCC(rwyCC)
    }
  }
}

extension Contamination {
  /// The recorded depth in inches, or nil for the conditions that carry none.
  ///
  /// Nil rather than zero: a condition with no depth says nothing about how deep the next one
  /// would be, so switching the picker from Wet Runway to Water/Slush starts at the depth the
  /// control opens at rather than at a depth that describes a clean runway.
  fileprivate var depthInches: Double? {
    switch self {
      case .waterOrSlush(let depth), .slushOrWetSnow(let depth):
        depth.converted(to: .inches).value
      case .drySnow, .compactSnow, .wetRunway, .rwyCC:
        nil
    }
  }
}

#Preview("RwyCC") {
  @State @Previewable var contamination: Contamination? = .rwyCC(3)

  List {
    ContaminationView(contamination: $contamination)
  }
}

#Preview("Depth") {
  @State @Previewable var contamination: Contamination? = .waterOrSlush(
    depth: .init(value: 0.3, unit: .inches)
  )

  List {
    ContaminationView(contamination: $contamination)
  }
}
