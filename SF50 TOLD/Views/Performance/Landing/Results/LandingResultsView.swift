import SF50_Shared
import SwiftUI

struct LandingResultsView: View {
  @Environment(LandingPerformanceViewModel.self)
  private var performance

  @Default(.useRegressionModel)
  private var useRegressionModel

  @Default(.VREFAdditive)
  private var VREFAdditive

  var body: some View {
    Section("Performance") {
      VREFView()
      VREFAdditiveView()
      LandingGroundRunView()
      LandingDistanceView()
      GoAroundClimbGradientView()

      if useRegressionModel && (performance.offscaleLow || performance.offscaleHigh) {
        OffscaleWarningView(
          offscaleLow: performance.offscaleLow,
          offscaleHigh: performance.offscaleHigh
        )
      }

      if performance.notam?.contamination != nil {
        ContaminationWarningView()
      }

      if VREFAdditive.value > 0 {
        VREFAdditiveWarningView()
      }
    }
  }
}

#Preview {
  PreviewView(insert: .KSQL) { helper in
    let runway = try helper.load(airportID: "SQL", runway: "30")!
    helper.setLanding(runway: runway)

    return List { LandingResultsView() }
      .environment(LandingPerformanceViewModel(container: helper.container))
      .environment(WeatherViewModel(operation: .landing, container: helper.container))
  }
}
