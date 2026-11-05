import Foundation
import MeasurementKit
import SF50_Shared

/// Generates landing performance data for all runways and scenarios.
///
/// ``LandingReportData`` extends ``BaseReportData`` with landing-specific calculations:
/// - Vref (reference speed)
/// - Landing ground run and total distance from 50'
/// - Go-around climb gradient compliance
/// - Maximum landing weight considering field length, AFM limits, and climb requirements
///
/// ## Weight Determination
///
/// The ``determineMaxWeight(runway:)`` method uses the package's limit search to find the
/// highest weight that satisfies:
/// 1. AFM performance chart limits
/// 2. Landing distance available
/// 3. Go-around climb gradient requirements
class LandingReportData: BaseReportData<LandingRunwayPerformance, LandingPerformanceScenario> {

  // MARK: - Template Method Overrides

  override func createScenario(name: String, runways: [RunwayInput: LandingRunwayPerformance])
    -> LandingPerformanceScenario
  {
    LandingPerformanceScenario(scenarioName: name, runways: runways)
  }

  override func calculatePerformance(
    for runway: RunwayInput,
    conditions: Conditions,
    config: Configuration
  ) throws -> LandingRunwayPerformance {
    let report = try calculator.landing(
      conditions: conditions,
      configuration: config,
      runway: runway,
      safetyFactor: input.safetyFactor
    )

    let available = runway.availableLandingDistance
    let landingRun = report.results.landingRun.map { value, uncertainty in
      (
        PerformanceDistance(distance: value, availableDistance: available),
        uncertainty.map { PerformanceDistance(distance: $0, availableDistance: available) }
      )
    }
    let landingDistance = report.results.landingDistance.map { value, uncertainty in
      (
        PerformanceDistance(distance: value, availableDistance: available),
        uncertainty.map { PerformanceDistance(distance: $0, availableDistance: available) }
      )
    }

    // Determine if valid based on landing distance and go-around requirement. A clamped distance
    // still answers the question, since it is the AFM's own figure for conditions milder than the
    // ones asked for; only a refusal carrying no figure leaves the runway untested.
    let isValid =
      landingDistance.flatMap { dist in
        report.results.meetsGoAroundClimbGradient.map { meetsReq in
          dist.margin >= .zero && meetsReq
        }
      }.nominalOrClamped ?? false

    return LandingRunwayPerformance(
      Vref: report.results.Vref,
      landingRun: landingRun,
      landingDistance: landingDistance,
      meetsGoAroundRequirement: report.results.meetsGoAroundClimbGradient,
      isValid: isValid
    )
  }

  override func determineMaxWeight(runway: RunwayInput) throws -> (
    Measurement<UnitMass>, LimitingFactor
  ) {
    maxWeight(
      from: try calculator.maxLandingWeight(
        conditions: input.conditions,
        runway: runway,
        flapSetting: input.flapSetting.performanceFlapSetting,
        minimumWeight: input.emptyWeight,
        safetyFactor: input.safetyFactor
      )
    )
  }
}
