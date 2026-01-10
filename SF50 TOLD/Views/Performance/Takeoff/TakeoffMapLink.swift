import SF50_Shared
import SwiftUI

/// Navigation link to the runway map view for takeoff visualization.
///
/// This link is disabled when:
/// - The runway lacks threshold coordinates
/// - The takeoff ground run is not available (e.g., inputs are incomplete or offscale)
struct TakeoffMapLink: View {
  @Environment(TakeoffPerformanceViewModel.self)
  private var performance

  /// Whether the map can be shown based on available data.
  private var canShowMap: Bool {
    guard let runway = performance.runway,
      runway.hasThresholdCoordinates
    else { return false }

    // Check if we have a valid takeoff run value
    switch performance.takeoffRun {
      case .value, .valueWithUncertainty:
        return true
      default:
        return false
    }
  }

  /// Extract the ground run distance from the Value enum.
  private var groundRun: Measurement<UnitLength>? {
    switch performance.takeoffRun {
      case .value(let distance):
        return distance
      case .valueWithUncertainty(let distance, _):
        return distance
      default:
        return nil
    }
  }

  var body: some View {
    if let runway = performance.runway,
      let groundRun
    {
      NavigationLink {
        RunwayMapView(
          runway: runway,
          groundRun: groundRun,
          operation: SF50_Shared.Operation.takeoff,
          notamOffset: performance.notam?.takeoffDistanceShortening ?? .init(value: 0, unit: .feet)
        )
      } label: {
        Text("Show Takeoff…")
      }
      .accessibilityIdentifier("showTakeoffMapButton")
      .disabled(!canShowMap)
    } else {
      Text("Show Takeoff…")
        .foregroundStyle(.tertiary)
        .accessibilityIdentifier("showTakeoffMapButton")
    }
  }
}

#Preview("Enabled") {
  PreviewView(insert: .KOAK) { helper in
    let runway = try helper.load(airportID: "OAK", runway: "28R")!
    helper.setTakeoff(runway: runway)

    return NavigationStack {
      List {
        TakeoffMapLink()
      }
    }
    .environment(TakeoffPerformanceViewModel(container: helper.container))
  }
}

#Preview("Disabled - No Coordinates") {
  PreviewView(insert: .KOAK) { helper in
    // Runway 15 doesn't have threshold coordinates in the fixture
    let runway = try helper.load(airportID: "OAK", runway: "15")!
    helper.setTakeoff(runway: runway)

    return NavigationStack {
      List {
        TakeoffMapLink()
      }
    }
    .environment(TakeoffPerformanceViewModel(container: helper.container))
  }
}
