import AppIntents
import SF50_Shared
import SwiftUI
import WidgetKit

/// Widget displaying takeoff or landing performance for every runway at a chosen airport.
///
/// ## Supported Sizes
///
/// - **Small**: A pass/fail mark per runway
/// - **Medium**: Required against available distance, with wind components
///
/// ## Configuration
///
/// The airport, the leg, and the landing flap setting are all editable on the widget itself, so two
/// pinned widgets can show departure and destination at the same time.
struct SelectedAirportPerformanceWidget: Widget {
  let kind: String = "SF50_SelectedAirport"

  var body: some WidgetConfiguration {
    AppIntentConfiguration(
      kind: kind,
      intent: SelectedAirportConfigurationIntent.self,
      provider: TOLDProvider()
    ) { entry in
      SelectedAirportWidgetEntryView(entry: entry)
    }
    .configurationDisplayName("SF50 Airport Performance")
    .description(
      "Shows every runway at an airport and whether the aircraft can make it, using current weather and the payload and fuel entered in the app."
    )
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}

#Preview("Small", as: .systemSmall) {
  SelectedAirportPerformanceWidget()
} timeline: {
  RunwayWidgetEntry.empty()
}

#Preview("Medium", as: .systemMedium) {
  SelectedAirportPerformanceWidget()
} timeline: {
  RunwayWidgetEntry.empty()
}
