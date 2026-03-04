import SF50_Shared
import SwiftUI

struct LandingAdjustmentsView: View {
  @Environment(LandingPerformanceViewModel.self)
  private var performance

  var body: some View {
    List {
      if let report = performance.landingReport {
        BreakdownSection(
          title: String(localized: "Ground Run"),
          breakdown: report.groundRunBreakdown,
          total: report.results.landingRun,
          maximum: performance.availableLandingRun
        )
        BreakdownSection(
          title: String(localized: "Total Distance"),
          breakdown: report.distanceBreakdown,
          total: report.results.landingDistance,
          maximum: performance.availableLandingRun
        )
      }
      if !performance.notes.isEmpty {
        NotesSection(notes: performance.notes)
      }
    }
    .navigationTitle("Landing Adjustments")
  }
}

#Preview {
  PreviewView(insert: .KSQL) { helper in
    let runway = try helper.load(airportID: "SQL", runway: "30")!
    helper.setLanding(runway: runway)

    return NavigationStack {
      LandingAdjustmentsView()
    }
    .environment(LandingPerformanceViewModel(container: helper.container))
  }
}

#Preview("Strong Winds") {
  PreviewView(insert: .KSQL) { helper in
    let runway = try helper.load(airportID: "SQL", runway: "30")!
    helper.setLanding(runway: runway)
    let performance = LandingPerformanceViewModel(container: helper.container)
    performance.conditions = helper.strongWinds

    return NavigationStack {
      LandingAdjustmentsView()
    }
    .environment(performance)
  }
}
