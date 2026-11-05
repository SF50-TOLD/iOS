import Foundation
import MeasurementKit
import SF50_Shared

/// Generates takeoff performance data for all runways and scenarios.
///
/// ``TakeoffReportData`` extends ``BaseReportData`` with takeoff-specific calculations:
/// - Ground run and total distance to 50'
/// - Climb gradient
/// - Maximum takeoff weight considering field length, AFM limits, and obstacle clearance
///
/// ## Weight Determination
///
/// The ``determineMaxWeight(runway:)`` method uses the package's limit search to find the
/// highest weight that satisfies:
/// 1. AFM performance chart limits
/// 2. Takeoff run and distance available
/// 3. Obstacle clearance from the 50 ft screen (if a NOTAM specifies an obstacle)
class TakeoffReportData: BaseReportData<TakeoffRunwayPerformance, TakeoffPerformanceScenario> {

  // MARK: - Template Method Overrides

  override func createScenario(name: String, runways: [RunwayInput: TakeoffRunwayPerformance])
    -> TakeoffPerformanceScenario
  {
    TakeoffPerformanceScenario(scenarioName: name, runways: runways)
  }

  override func calculatePerformance(
    for runway: RunwayInput,
    conditions: Conditions,
    config: Configuration
  ) throws -> TakeoffRunwayPerformance {
    let perfModel = try calculator.model(
      conditions: conditions,
      configuration: config,
      runway: runway
    )
    let report = try performance.calculateTakeoff(
      for: perfModel,
      safetyFactor: input.safetyFactor
    )

    let availableRun = runway.availableTakeoffRun,
      availableDistance = runway.availableTakeoffDistance
    let groundRun = report.results.takeoffRun.map { value, uncertainty in
      (
        PerformanceDistance(distance: value, availableDistance: availableRun),
        uncertainty.map { PerformanceDistance(distance: $0, availableDistance: availableRun) }
      )
    }
    let totalDistance = report.results.takeoffDistance.map { value, uncertainty in
      (
        PerformanceDistance(distance: value, availableDistance: availableDistance),
        uncertainty.map { PerformanceDistance(distance: $0, availableDistance: availableDistance) }
      )
    }
    let climbRate = report.results.takeoffClimbGradient

    let isValid = hasMargin(groundRun) && hasMargin(totalDistance)

    return TakeoffRunwayPerformance(
      groundRun: groundRun,
      totalDistance: totalDistance,
      climbRate: climbRate,
      isValid: isValid
    )
  }

  override func determineMaxWeight(runway: RunwayInput) throws -> (
    Measurement<UnitMass>, LimitingFactor
  ) {
    maxWeight(
      from: try calculator.maxTakeoffWeight(
        conditions: input.conditions,
        runway: runway,
        minimumWeight: input.emptyWeight,
        safetyFactor: input.safetyFactor
      )
    )
  }

  // MARK: - Runway Fit

  /// Whether a calculated distance is known and leaves the runway it was measured against.
  private func hasMargin(_ distance: Value<PerformanceDistance>) -> Bool {
    guard let distance = distance.nominal else { return false }
    return distance.margin >= .zero
  }
}
