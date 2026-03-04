import SF50_Shared
import SwiftUI

struct LandingResultsView: View {
  @Environment(LandingPerformanceViewModel.self)
  private var performance

  private var adjustmentsLabel: String {
    if performance.notes.contains(where: { $0.severity == .warning }) {
      return String(localized: "Adjustments and Operational Warnings…")
    }
    if !performance.notes.isEmpty {
      return String(localized: "Adjustments and Operational Notes…")
    }
    return String(localized: "Adjustments…")
  }

  var body: some View {
    Section("Performance") {
      VREFView()
      VREFAdditiveView()
      LandingGroundRunView()
      LandingDistanceView()
      GoAroundClimbGradientView()
    }

    if performance.landingReport != nil {
      Section {
        NavigationLink {
          LandingAdjustmentsView()
        } label: {
          Text(adjustmentsLabel)
        }
        .badge(performance.notes.count)
        .badgeProminence(
          performance.notes.contains { $0.severity == .warning } ? .increased : .standard
        )
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
