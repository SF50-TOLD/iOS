import SF50_Shared
import SwiftUI

/// Navigation link to the runway map view for landing visualization.
///
/// This link is disabled when:
/// - The runway lacks threshold coordinates
/// - The landing ground run is not available (e.g., inputs are incomplete or offscale)
struct LandingMapLink: View {
  @Environment(LandingPerformanceViewModel.self)
  private var performance

  /// Whether the map can be shown based on available data.
  private var canShowMap: Bool {
    guard let runway = performance.runway,
      runway.hasThresholdCoordinates
    else { return false }

    // Check if we have a valid landing run value
    switch performance.landingRun {
      case .value, .valueWithUncertainty:
        return true
      default:
        return false
    }
  }

  /// Extract the ground run distance from the Value enum.
  private var groundRun: Measurement<UnitLength>? {
    switch performance.landingRun {
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
          operation: SF50_Shared.Operation.landing,
          notamOffset: performance.notam?.landingDistanceShortening ?? .init(value: 0, unit: .feet),
          shorteningLocation: performance.notam?.landingShorteningLocation ?? .departureEnd
        )
      } label: {
        Text("Show Landing…")
      }
      .accessibilityIdentifier("showLandingMapButton")
      .disabled(!canShowMap)
    } else {
      Text("Show Landing…")
        .foregroundStyle(.tertiary)
        .accessibilityIdentifier("showLandingMapButton")
    }
  }
}

#Preview("Enabled") {
  PreviewView(insert: .KSQL) { helper in
    let runway = try helper.load(airportID: "SQL", runway: "30")!
    helper.setLanding(runway: runway)

    return NavigationStack {
      List {
        LandingMapLink()
      }
    }
    .environment(LandingPerformanceViewModel(container: helper.container))
  }
}

#Preview("Disabled - No Coordinates") {
  PreviewView(insert: .KOAK) { helper in
    // Runway 15 doesn't have threshold coordinates in the fixture
    let runway = try helper.load(airportID: "OAK", runway: "15")!
    helper.setLanding(runway: runway)

    return NavigationStack {
      List {
        LandingMapLink()
      }
    }
    .environment(LandingPerformanceViewModel(container: helper.container))
  }
}
