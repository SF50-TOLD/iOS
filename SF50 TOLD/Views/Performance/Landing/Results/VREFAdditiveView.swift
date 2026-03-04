import Defaults
import SF50_Shared
import SwiftUI

struct VREFAdditiveView: View {
  @Default(.VREFAdditive)
  private var VREFAdditive

  @Default(.speedUnit)
  private var speedUnit

  var body: some View {
    LabeledContent {
      MeasurementField(
        "Speed",
        value: $VREFAdditive,
        unit: speedUnit,
        format: .speed(plusSign: true),
        minimum: .init(value: 0, unit: .knots)
      )
    } label: {
      Text(.VREF + AttributedString(" Additive"))
    }
  }
}

#Preview("Zero") {
  PreviewView(insert: .KSQL) { preview in
    let runway = try preview.load(airportID: "SQL", runway: "30")!
    preview.setLanding(runway: runway)

    return List {
      VREFAdditiveView()
    }
    .environment(LandingPerformanceViewModel(container: preview.container))
  }
}

#Preview("Non-Zero") {
  PreviewView(insert: .KSQL) { preview in
    let runway = try preview.load(airportID: "SQL", runway: "30")!
    preview.setLanding(runway: runway)
    Defaults[.VREFAdditive] = .init(value: 5, unit: .knots)

    return List {
      VREFAdditiveView()
    }
    .environment(LandingPerformanceViewModel(container: preview.container))
  }
}
