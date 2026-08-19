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
/// 2. Available runway length
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

    let groundRun = report.results.takeoffRun.map { value, uncertainty in
      (
        PerformanceDistance(distance: value, availableDistance: runway.length),
        uncertainty.map { PerformanceDistance(distance: $0, availableDistance: runway.length) }
      )
    }
    let totalDistance = report.results.takeoffDistance.map { value, uncertainty in
      (
        PerformanceDistance(distance: value, availableDistance: runway.length),
        uncertainty.map { PerformanceDistance(distance: $0, availableDistance: runway.length) }
      )
    }
    let climbRate = report.results.takeoffClimbGradient

    // Determine if valid based on total distance
    let isValid: Bool = {
      switch totalDistance {
        case .value(let dist), .valueWithUncertainty(let dist, _):
          return dist.margin >= .zero
        default:
          return false
      }
    }()

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
      if case .value(let dist) = report.results.takeoffDistance {
        // Check runway length
        if dist > runway.length {
          return (false, .field)
        }
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
}
