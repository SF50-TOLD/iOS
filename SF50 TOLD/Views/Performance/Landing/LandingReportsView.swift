import Defaults
import SF50_Shared
import SwiftUI

struct LandingReportsView: View {
  @Default(.landingAirport)
  private var airportID

  @Default(.landingRunway)
  private var runwayID

  var body: some View {
    if airportID != nil {
      LandingReportButton()
    } else {
      Text("Generate Landing Report…")
        .foregroundStyle(.tertiary)
    }
    LandingMapLink()
    if runwayID != nil {
      NavigationLink("Show Go-Around…") {
        GoAroundProfileView()
      }
    } else {
      Text("Show Go-Around…")
        .foregroundStyle(.tertiary)
    }
  }
}

#Preview("Enabled") {
  PreviewView(insert: .KOAK) { helper in
    let runway = try helper.load(airportID: "OAK", runway: "28R")!
    helper.setLanding(runway: runway)

    return NavigationStack {
      List {
        LandingReportsView()
      }
    }
    .environment(LandingPerformanceViewModel(container: helper.container))
    .environment(WeatherViewModel(operation: .landing, container: helper.container))
  }
}

#Preview("Disabled") {
  PreviewView(insert: .KOAK) { helper in
    NavigationStack {
      List {
        LandingReportsView()
      }
    }
    .environment(LandingPerformanceViewModel(container: helper.container))
    .environment(WeatherViewModel(operation: .landing, container: helper.container))
  }
}
