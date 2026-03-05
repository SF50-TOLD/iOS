import SF50_Shared
import SwiftUI

struct TakeoffResultsView: View {
  @Environment(TakeoffPerformanceViewModel.self)
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
      TakeoffGroundRunView()
      TakeoffDistanceView()
      VxClimbView()
    }

    if performance.takeoffReport != nil {
      Section {
        NavigationLink {
          TakeoffAdjustmentsView()
        } label: {
          Text(adjustmentsLabel)
        }
        .accessibilityIdentifier("takeoffAdjustmentsLink")
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
    helper.setTakeoff(runway: runway)

    return List { TakeoffResultsView() }
      .environment(TakeoffPerformanceViewModel(container: helper.container))
      .environment(WeatherViewModel(operation: .takeoff, container: helper.container))
  }
}
