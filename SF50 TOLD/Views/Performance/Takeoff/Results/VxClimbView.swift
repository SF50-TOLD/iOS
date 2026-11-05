import MeasurementKit
import SF50_Shared
import SwiftUI

struct VxClimbView: View {
  @Environment(TakeoffPerformanceViewModel.self)
  private var performance

  private var vxText: AttributedString {
    let v = AttributedString("V")
    var x = AttributedString("X")
    x.font = .system(size: 10.0)
    x.baselineOffset = -3.0

    return v + x
  }

  private var unmetClimbRequirement: ClimbRequirement? {
    guard let requirement = performance.climbRequirement,
      !requirement.isMet(by: performance.takeoffClimbGradient.nominalOrClamped)
    else {
      return nil
    }
    return requirement
  }

  private var obstacleWithinTakeoffDistanceDescription: String? {
    performance.notes.first {
      if case .obstacleWithinTakeoffDistance = $0 { true } else { false }
    }?.preferredDescription
  }

  private var sufficientRunway: Bool {
    guard let availableTakeoffRun = performance.availableTakeoffRun,
      let takeoffRun = performance.takeoffRun.nominalOrClamped
    else {
      return true
    }
    return takeoffRun <= availableTakeoffRun
  }

  var body: some View {
    LabeledContent(
      content: {
        InterpolationView(
          value: performance.takeoffClimbGradient,
          minimum: performance.requiredClimbGradient,
          maxCritical: false,
          displayValue: { Text($0.asGradient, format: .gradient).fontWeight(.semibold) },
          displayUncertainty: { Text("±\($0.asGradient, format: .gradient)") }
        )
        .accessibilityIdentifier("vxClimbGradientValue")
        .animation(.default, value: performance.takeoffClimbGradient)
      },
      label: {
        Text("\(vxText) Climb Gradient")
      }
    )

    if sufficientRunway, let unmetClimbRequirement {
      HStack {
        climbWarning(for: unmetClimbRequirement)
          .font(.subheadline)
          .foregroundColor(.red)
      }
    }

    LabeledContent(
      content: {
        InterpolationView(
          value: performance.takeoffClimbRate,
          minimum: .init(value: 0, unit: .feetPerMinute),
          maxCritical: false,
          displayValue: { Text($0, format: .rateOfClimb).fontWeight(.semibold) },
          displayUncertainty: { Text("±\($0, format: .rateOfClimb)") }
        )
        .accessibilityIdentifier("vxClimbRateValue")
        .animation(.default, value: performance.takeoffClimbRate)
      },
      label: {
        Text("\(vxText) Climb Rate")
      }
    )
  }

  @ViewBuilder
  private func climbWarning(for requirement: ClimbRequirement) -> some View {
    switch requirement {
      case .gradient(let required):
        Label(
          "A climb gradient of \(required.asGradient, format: .gradient) is required.",
          systemImage: "exclamationmark.triangle"
        )
      case .unclearable:
        if let obstacleWithinTakeoffDistanceDescription {
          Label(obstacleWithinTakeoffDistanceDescription, systemImage: "exclamationmark.triangle")
        }
      case .none:
        EmptyView()
    }
  }
}

#Preview("No Obstacle") {
  PreviewView(insert: .KSQL) { preview in
    let runway = try preview.load(airportID: "SQL", runway: "30")!
    preview.setTakeoff(runway: runway)

    return List {
      VxClimbView()
    }
    .environment(TakeoffPerformanceViewModel(container: preview.container))
  }
}

#Preview("Possible") {
  PreviewView(insert: .KSQL) { preview in
    let runway = try preview.load(airportID: "SQL", runway: "30")!
    preview.setTakeoff(runway: runway)
    try preview.addNOTAM(to: runway, obstacleHeight: 100, obstacleDistance: 0.1)

    return List {
      VxClimbView()
    }
    .environment(TakeoffPerformanceViewModel(container: preview.container))
  }
}

#Preview("Impossible") {
  PreviewView(insert: .KOAK) { preview in
    let runway = try preview.load(airportID: "OAK", runway: "30")!
    preview.setTakeoff(runway: runway)
    try preview.addNOTAM(to: runway, obstacleHeight: 800, obstacleDistance: 0.1)

    let performance = TakeoffPerformanceViewModel(container: preview.container)
    performance.conditions = preview.veryHot

    return List {
      VxClimbView()
    }
    .environment(performance)
  }
}

#Preview("Unclearable") {
  PreviewView(insert: .KSQL) { preview in
    let runway = try preview.load(airportID: "SQL", runway: "30")!
    preview.setTakeoff(runway: runway)
    try preview.addNOTAM(to: runway, obstacleHeight: 200, obstacleDistance: 0.01)

    return List {
      VxClimbView()
    }
    .environment(TakeoffPerformanceViewModel(container: preview.container))
  }
}

#Preview("Exceeds Runway Length") {
  PreviewView(insert: .KSQL) { preview in
    let runway = try preview.load(airportID: "SQL", runway: "30")!
    preview.setTakeoff(runway: runway)
    try preview.addNOTAM(to: runway, obstacleHeight: 100, obstacleDistance: 0.1)

    let performance = TakeoffPerformanceViewModel(container: preview.container)
    performance.conditions = preview.veryHot

    return List {
      VxClimbView()
    }
    .environment(performance)
  }
}

#Preview("N/A") {
  PreviewView(insert: .KSQL) { preview in
    List {
      VxClimbView()
    }
    .environment(TakeoffPerformanceViewModel(container: preview.container))
  }
}
