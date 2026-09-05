import AppIntents
import SF50_Shared
import SwiftUI
import WidgetKit

/// Timeline provider for the SF50 Runways widget.
///
/// ## Timeline Behavior
///
/// - **Placeholder**: An empty entry, drawn redacted while the widget loads
/// - **Snapshot**: A fixed sample for the gallery, or one real entry for a live preview
/// - **Timeline**: One entry with a 15-minute refresh policy, so a new METAR is picked up
///
/// Settings changes in the app trigger an immediate refresh through
/// `WidgetCenter.reloadTimelines(ofKind:)`.
struct TOLDProvider: AppIntentTimelineProvider {
  func placeholder(in _: Context) -> RunwayWidgetEntry { .empty() }

  func snapshot(
    for configuration: SelectedAirportConfigurationIntent,
    in context: Context
  ) async -> RunwayWidgetEntry {
    guard !context.isPreview else {
      return await .sample(operation: configuration.operation)
    }
    return await entry(for: configuration)
  }

  func timeline(
    for configuration: SelectedAirportConfigurationIntent,
    in _: Context
  ) async -> Timeline<RunwayWidgetEntry> {
    .init(
      entries: [await entry(for: configuration)],
      policy: .after(Date().addingTimeInterval(Self.refreshInterval))
    )
  }
}

extension TOLDProvider {
  /// Weather is republished hourly, so a quarter-hour cadence picks up a new observation promptly
  /// without asking the system for a budget it will not grant.
  private static let refreshInterval: TimeInterval = 900

  private func entry(for configuration: SelectedAirportConfigurationIntent) async
    -> RunwayWidgetEntry
  {
    let operation = configuration.operation
    do {
      let performance = try await RunwayPerformanceService()
        .performance(
          airportRecordID: configuration.airport?.id,
          operation: operation,
          flapSetting: configuration.flapSetting
        )
      return .init(date: Date(), performance: performance)
    } catch {
      return .empty(operation: operation)
    }
  }
}
