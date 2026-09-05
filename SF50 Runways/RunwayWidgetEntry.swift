import Foundation
import SF50_Shared
import WidgetKit

/// A timeline entry holding one airport's runway performance at one moment.
///
/// ## Empty State
///
/// ``empty(operation:)`` covers every reason there is nothing to show — no airport selected, a store
/// that needs reimporting, an airport that is no longer in the database — because the widget's answer
/// is the same in all of them: prompt the reader to open the app.
struct RunwayWidgetEntry: TimelineEntry, Sendable {
  /// When this timeline entry should be displayed.
  let date: Date

  /// The leg these numbers were calculated for.
  let operation: SF50_Shared.Operation

  /// Name of the airport being shown, or `nil` if there is nothing to show.
  let airportName: String?

  /// Snapshot of runway data for display.
  let runways: [RunwaySnapshot]?

  /// Weather conditions used for performance calculations.
  let conditions: Conditions?

  /// Calculated performance for each runway, keyed by runway name.
  let results: [String: RunwayPerformance]?

  /// The reference speed to show beside the airport name on a landing.
  ///
  /// VREF is a function of weight, flaps and conditions, not of the runway, so every runway's answer
  /// is the same number — but a runway whose calculation refused carries none, and dictionary order is
  /// arbitrary. Walking the runways in their displayed order and taking the first real answer keeps
  /// the header stable between refreshes.
  var VREF: Value<Measurement<UnitSpeed>>? {
    guard let runways, let results else { return nil }
    let speeds =
      runways
      .sorted(using: RunwaySnapshot.NameComparator())
      .compactMap { results[$0.name]?.VREF }
    return speeds.first { $0.nominal != nil } ?? speeds.first
  }

  /// Wraps a calculated result for display.
  ///
  /// - Parameters:
  ///   - date: When the entry becomes valid.
  ///   - performance: The calculated airport performance.
  init(date: Date, performance: AirportPerformance) {
    self.date = date
    operation = performance.operation
    airportName = performance.airportName
    runways = performance.runways
    conditions = performance.conditions
    results = performance.conditions == nil ? nil : performance.results
  }

  private init(date: Date, operation: SF50_Shared.Operation) {
    self.date = date
    self.operation = operation
    airportName = nil
    runways = nil
    conditions = nil
    results = nil
  }

  /// Creates an entry for when there is no airport to show.
  ///
  /// - Parameter operation: The leg the widget is configured for.
  /// - Returns: An entry the views render as a prompt to open the app.
  static func empty(operation: SF50_Shared.Operation = .takeoff) -> Self {
    .init(date: Date(), operation: operation)
  }
}
