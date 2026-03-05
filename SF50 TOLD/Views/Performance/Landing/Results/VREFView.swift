import Defaults
import SF50_Shared
import SwiftUI

struct VREFView: View {
  @Environment(LandingPerformanceViewModel.self)
  private var performance

  @Default(.speedUnit)
  private var speedUnit

  var body: some View {
    LabeledContent {
      InterpolationView(
        value: performance.Vref,
        displayValue: { Text($0.converted(to: speedUnit), format: .speed) },
        displayUncertainty: { Text("±\($0.converted(to: speedUnit), format: .speed)") }
      )
      .accessibilityIdentifier("VREFValue")
      .animation(.default, value: performance.Vref)
    } label: {
      Text(.VREF)
    }
  }
}

#Preview("VREF") {
  PreviewView(insert: .KSQL) { preview in
    let runway = try preview.load(airportID: "SQL", runway: "30")!
    preview.setLanding(runway: runway)

    return List {
      VREFView()
    }
    .environment(LandingPerformanceViewModel(container: preview.container))
  }
}

#Preview("N/A") {
  PreviewView(insert: .KSQL) { preview in
    List {
      VREFView()
    }
    .environment(LandingPerformanceViewModel(container: preview.container))
  }
}
