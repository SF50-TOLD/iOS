import SF50_Shared
import SwiftUI

struct TakeoffAdjustmentsView: View {
  @Environment(TakeoffPerformanceViewModel.self)
  private var performance

  var body: some View {
    List {
      if let report = performance.takeoffReport {
        BreakdownSection(
          title: String(localized: "Ground Run"),
          breakdown: report.groundRunBreakdown,
          total: report.results.takeoffRun,
          maximum: performance.availableTakeoffRun
        )
        BreakdownSection(
          title: String(localized: "Total Distance"),
          breakdown: report.distanceBreakdown,
          total: report.results.takeoffDistance,
          maximum: performance.availableTakeoffDistance
        )
      }
      if !performance.notes.isEmpty {
        NotesSection(notes: performance.notes)
      }
    }
    .navigationTitle("Takeoff Adjustments")
  }
}

#Preview {
  PreviewView(insert: .KSQL) { helper in
    let runway = try helper.load(airportID: "SQL", runway: "30")!
    helper.setTakeoff(runway: runway)

    return NavigationStack {
      TakeoffAdjustmentsView()
    }
    .environment(TakeoffPerformanceViewModel(container: helper.container))
  }
}

#Preview("Strong Winds") {
  PreviewView(insert: .KSQL) { helper in
    let runway = try helper.load(airportID: "SQL", runway: "30")!
    helper.setTakeoff(runway: runway)
    let performance = TakeoffPerformanceViewModel(container: helper.container)
    performance.conditions = helper.strongWinds

    return NavigationStack {
      TakeoffAdjustmentsView()
    }
    .environment(performance)
  }
}
