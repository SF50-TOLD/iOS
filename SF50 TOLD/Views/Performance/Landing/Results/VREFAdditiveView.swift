import Defaults
import SF50_Shared
import SwiftUI

struct VREFAdditiveView: View {
  @Default(.VREFAdditive)
  private var VREFAdditive

  @Default(.speedUnit)
  private var speedUnit

  private var vrefAdditiveText: AttributedString {
    let v = AttributedString("V")
    var ref = AttributedString("REF")
    ref.font = .system(size: 10.0)
    ref.baselineOffset = -3.0

    return v + ref + AttributedString(" Additive")
  }

  var body: some View {
    LabeledContent(
      content: {
        MeasurementField(
          "Speed",
          value: $VREFAdditive,
          unit: speedUnit,
          format: .speed(plusSign: true),
          minimum: .init(value: 0, unit: .knots)
        )
      },
      label: {
        Text(vrefAdditiveText)
      }
    )
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
