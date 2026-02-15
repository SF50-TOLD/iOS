import Defaults
import SF50_Shared
import SwiftUI

struct TakeoffReportsView: View {
  @Default(.takeoffAirport)
  private var airportID

  @Default(.takeoffRunway)
  private var runwayID

  var body: some View {
    if airportID != nil {
      TakeoffReportButton()
    } else {
      Text("Generate Takeoff Report…")
        .foregroundStyle(.tertiary)
    }
    TakeoffMapLink()
    if runwayID != nil {
      NavigationLink("Show Climb…") {
        ClimbProfileView()
      }
    } else {
      Text("Show Climb…")
        .foregroundStyle(.tertiary)
    }
  }
}

#Preview("Enabled") {
  PreviewView(insert: .KOAK) { helper in
    let runway = try helper.load(airportID: "OAK", runway: "28R")!
    helper.setTakeoff(runway: runway)

    return NavigationStack {
      List {
        TakeoffReportsView()
      }
    }
    .environment(TakeoffPerformanceViewModel(container: helper.container))
    .environment(WeatherViewModel(operation: .takeoff, container: helper.container))
  }
}

#Preview("Disabled") {
  PreviewView(insert: .KOAK) { helper in
    NavigationStack {
      List {
        TakeoffReportsView()
      }
    }
    .environment(TakeoffPerformanceViewModel(container: helper.container))
    .environment(WeatherViewModel(operation: .takeoff, container: helper.container))
  }
}
