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
/// The ``determineMaxWeight(runway:)`` method uses binary search to find the highest
/// weight that satisfies:
/// 1. AFM performance chart limits
/// 2. Takeoff distance available
/// 3. Obstacle clearance (if NOTAM specifies obstacles)
class TakeoffReportData: BaseReportData<TakeoffRunwayPerformance, TakeoffPerformanceScenario> {

  // MARK: - Template Method Overrides

  override func maxWeight() -> Measurement<UnitMass> {
    LimitationsG2Plus.maxTakeoffWeight
  }

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
    let perfModel = performance.createPerformanceModel(
      conditions: conditions,
      configuration: config,
      runway: runway,
      notam: runway.notam,
      useRegressionModel: input.useRegressionModel,
      aircraftType: input.aircraftType
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
    let result = try binarySearchMaxWeight(
      runway: runway,
      min: input.emptyWeight,
      max: maxWeight()
    ) { weight -> (valid: Bool, factor: LimitingFactor) in
      let config = Configuration(
        weight: weight,
        flapSetting: input.flapSetting
      )

      let model = performance.createPerformanceModel(
        conditions: input.conditions,
        configuration: config,
        runway: runway,
        notam: runway.notam,
        useRegressionModel: input.useRegressionModel,
        aircraftType: input.aircraftType
      )
      let report = try performance.calculateTakeoff(
        for: model,
        safetyFactor: input.safetyFactor
      )

      // Check AFM limits
      if case .offscaleHigh = report.results.takeoffDistance {
        return (false, .AFM)
      }
      if case .offscaleLow = report.results.takeoffDistance {
        return (false, .AFM)
      }
      if !fitsRunway(report.results, on: runway) {
        return (false, .field)
      }

      // Check obstacle clearance if NOTAM present
      if let obstacleHeight = runway.notam?.obstacleHeight,
        let obstacleDistance = runway.notam?.obstacleDistance,
        case .value(let takeoffRun) = report.results.takeoffRun
      {
        let distanceFromRunwayStart =
          obstacleDistance + (runway.notam?.takeoffDistanceShortening ?? .zero)
        let distanceFromLiftoff = distanceFromRunwayStart - takeoffRun

        if distanceFromLiftoff > .zero {
          let requiredGradient = Measurement(
            value: obstacleHeight / distanceFromLiftoff,
            unit: UnitSlope.ratio
          )

          if case .value(let climbGradient) = report.results.takeoffClimbGradient,
            climbGradient < requiredGradient
          {
            return (false, .obstacle)
          }
        }
      }

      return (true, .AFM)
    }

    return (result.weight, result.limitingFactor ?? .AFM)
  }

  // MARK: - Runway Fit

  /// Whether both takeoff distances fit what the runway declares.
  ///
  /// The ground run has to fit the takeoff run and the total distance the takeoff distance, which
  /// differ wherever a runway has a clearway: measuring the run against the longer of the two
  /// would pass a takeoff that lifts off beyond the end of the pavement.
  ///
  /// A distance the AFM cannot give is no verdict on the runway; the AFM checks answer for it.
  private func fitsRunway(_ results: TakeoffResults, on runway: RunwayInput) -> Bool {
    fits(results.takeoffRun, within: runway.availableTakeoffRun)
      && fits(results.takeoffDistance, within: runway.availableTakeoffDistance)
  }

  private func fits(
    _ distance: Value<Measurement<UnitLength>>,
    within available: Measurement<UnitLength>
  ) -> Bool {
    guard let distance = distance.nominal else { return true }
    return distance <= available
  }

  /// Whether a calculated distance is known and leaves the runway it was measured against.
  private func hasMargin(_ distance: Value<PerformanceDistance>) -> Bool {
    guard let distance = distance.nominal else { return false }
    return distance.margin >= .zero
  }
}
