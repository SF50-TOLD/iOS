import AppIntents
import Foundation
import SF50_Shared
import SwiftUI

/// Draws the numbers ``RunwayNumbersIntent`` reports.
///
/// It carries the inputs rather than the answer so the system can re-run it and redraw with fresher
/// weather, which is also why every value is recalculated here instead of being handed across.
struct RunwayNumbersSnippetIntent: SnippetIntent {
  static let title: LocalizedStringResource = "Runway Numbers"

  static let isDiscoverable = false

  /// The `recordID` of the airport to calculate for.
  @Parameter(title: "Airport")
  var airportRecordID: String

  /// The runway designator.
  @Parameter(title: "Runway")
  var runwayName: String

  /// The leg to calculate.
  @Parameter(title: "Phase")
  var operation: SF50_Shared.Operation

  /// The landing flap configuration.
  @Parameter(title: "Landing Flaps")
  var flapSetting: FlapSetting

  init() {}

  /// Creates a snippet for one runway.
  ///
  /// - Parameters:
  ///   - airportRecordID: The `recordID` of the airport.
  ///   - runwayName: The runway designator.
  ///   - operation: The leg to calculate.
  ///   - flapSetting: The landing flap configuration.
  init(
    airportRecordID: String,
    runwayName: String,
    operation: SF50_Shared.Operation,
    flapSetting: FlapSetting
  ) {
    self.airportRecordID = airportRecordID
    self.runwayName = runwayName
    self.operation = operation
    self.flapSetting = flapSetting
  }

  @MainActor
  func perform() async throws -> some ShowsSnippetView {
    let performance = try await RunwayPerformanceService()
      .performance(
        airportRecordID: airportRecordID,
        operation: operation,
        flapSetting: flapSetting
      )

    guard let runway = performance.runway(named: runwayName) else {
      throw PerformanceLookupError.runwayNotFound(
        name: runwayName,
        airport: performance.airportDisplayID
      )
    }
    guard let conditions = performance.conditions else {
      throw PerformanceLookupError.weatherUnavailable(airport: performance.airportDisplayID)
    }

    return .result(
      view: RunwayNumbersSnippet(
        airportDisplayID: performance.airportDisplayID,
        runway: runway,
        operation: operation,
        flapSetting: flapSetting,
        performance: performance.results[runwayName],
        conditions: conditions
      )
    )
  }
}
