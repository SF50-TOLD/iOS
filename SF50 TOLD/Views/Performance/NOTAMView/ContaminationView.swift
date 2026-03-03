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
  @Binding var contamination: Contamination?

  @State private var contaminationType = ContaminationType.none
  @State private var contaminationDepth = 0.0
  @State private var rwyCC: UInt8 = 6

  private var contaminationDepthMeasurement: Measurement<UnitLength> {
    .init(value: contaminationDepth, unit: .inches)
  }

  private let minDepth = Measurement(value: 0, unit: UnitLength.inches)
  private let maxDepth = Measurement(value: 0.5, unit: UnitLength.inches)

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
            Text(minDepth, format: .depth)
              .foregroundStyle(.secondary)
            Slider(
              value: $contaminationDepth,
              in: minDepth.value...maxDepth.value,
              step: 0.1
            )
            .accessibilityIdentifier("contaminationDepthSlider")
            Text(maxDepth, format: .depth)
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
      contaminationDepth = contamination?.depth ?? 0
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
  fileprivate var depth: Double {
    switch self {
      case .waterOrSlush(let depth):
        depth.converted(to: .inches).value
      case .slushOrWetSnow(let depth):
        depth.converted(to: .inches).value
      case .drySnow, .compactSnow, .wetRunway:
        0.0
      case .rwyCC:
        0.0
    }
  }
}

#Preview {
  @State @Previewable var contamination: Contamination? = .rwyCC(3)

  List {
    ContaminationView(contamination: $contamination)
  }
}
