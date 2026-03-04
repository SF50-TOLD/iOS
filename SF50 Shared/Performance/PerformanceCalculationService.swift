import Defaults
import Foundation

/// Protocol for services that calculate aircraft takeoff and landing performance.
///
/// Implementations of ``PerformanceCalculationService`` take a configured
/// ``PerformanceModel`` and compute the resulting distances, speeds, and climb
/// performance with optional safety factors applied.
public protocol PerformanceCalculationService: Sendable {
  /**
   * Calculates takeoff performance for the given model.
   *
   * - Parameters:
   *   - model: The performance model configured with conditions, configuration, and runway.
   *   - safetyFactor: A multiplier applied to distance results (e.g., 1.15 for 15% safety margin).
   * - Returns: A takeoff report including results and distance breakdowns.
   */
  func calculateTakeoff(for model: PerformanceModel, safetyFactor: Double) throws -> TakeoffReport

  /**
   * Calculates landing performance for the given model.
   *
   * - Parameters:
   *   - model: The performance model configured with conditions, configuration, and runway.
   *   - safetyFactor: A multiplier applied to distance results (e.g., 1.15 for 15% safety margin).
   *   - VREFAdditiveKts: Additional speed above base VREF in knots. Per AC 91-79B section 5.2.2,
   *     each 10% increase in VREF adds 20% to landing distance.
   * - Returns: A landing report including results and distance breakdowns.
   */
  func calculateLanding(for model: PerformanceModel, safetyFactor: Double, VREFAdditiveKts: Double)
    throws -> LandingReport
}

/// Default implementation of ``PerformanceCalculationService``.
///
/// ``DefaultPerformanceCalculationService`` is a singleton service that creates
/// performance models and calculates takeoff/landing results. It selects the
/// appropriate performance model implementation based on aircraft generation
/// and user preferences.
public final class DefaultPerformanceCalculationService: PerformanceCalculationService {
  /// Shared singleton instance.
  public static let shared = DefaultPerformanceCalculationService()

  private init() {}

  /**
   * Creates a performance model appropriate for the aircraft type and preferences.
   *
   * - Parameters:
   *   - conditions: Atmospheric conditions (temperature, pressure, wind).
   *   - configuration: Aircraft configuration (weight, flaps).
   *   - runway: Runway data snapshot.
   *   - notam: Active NOTAM data if present.
   *   - useRegressionModel: Whether to use regression model (more accurate) vs tabular.
   *   - aircraftType: The user's configured aircraft type.
   * - Returns: A configured performance model ready for calculation.
   */
  public func createPerformanceModel(
    conditions: Conditions,
    configuration: Configuration,
    runway: RunwayInput,
    notam: NOTAMInput?,
    useRegressionModel: Bool,
    aircraftType: AircraftType
  ) -> PerformanceModel {
    if useRegressionModel {
      return RegressionPerformanceModel(
        conditions: conditions,
        configuration: configuration,
        runway: runway,
        notam: notam,
        aircraftType: aircraftType
      )
    }
    return TabularPerformanceModel(
      conditions: conditions,
      configuration: configuration,
      runway: runway,
      notam: notam,
      aircraftType: aircraftType
    )
  }

  public func calculateTakeoff(for model: PerformanceModel, safetyFactor: Double) throws
    -> TakeoffReport
  {
    let (runValue, runBreakdown) = model.computeDistance(for: .takeoffRun)
    let (distValue, distBreakdown) = model.computeDistance(for: .takeoffDistance)

    let (finalRun, runAdjustments) = applyPostAdjustments(
      to: runValue,
      safetyFactor: safetyFactor
    )
    let (finalDist, distAdjustments) = applyPostAdjustments(
      to: distValue,
      safetyFactor: safetyFactor
    )

    let results = TakeoffResults(
      takeoffRun: finalRun.toMeasurement(UnitLength.feet),
      takeoffDistance: finalDist.toMeasurement(UnitLength.feet),
      takeoffClimbGradient: model.takeoffClimbGradientFtNM.toMeasurement(
        UnitSlope.feetPerNauticalMile
      ),
      takeoffClimbRate: model.takeoffClimbRateFtMin.toMeasurement(UnitSpeed.feetPerMinute)
    )

    return TakeoffReport(
      results: results,
      groundRunBreakdown: runBreakdown.appending(runAdjustments),
      distanceBreakdown: distBreakdown.appending(distAdjustments)
    )
  }

  public func calculateLanding(
    for model: PerformanceModel,
    safetyFactor: Double,
    VREFAdditiveKts: Double = 0
  ) throws -> LandingReport {
    let (runValue, runBreakdown) = model.computeDistance(for: .landingRun)
    let (distValue, distBreakdown) = model.computeDistance(for: .landingDistance)

    // Per AC 91-79B section 5.2.2: each 10% increase in VREF adds 20% to landing distance.
    // Factor = 1 + 2 * (additiveKts / baseVrefKts)
    let VREFFactor: Value<Double> =
      if VREFAdditiveKts > 0 {
        model.VrefKts.map { 1 + 2 * (VREFAdditiveKts / $0) }
      } else {
        .value(1.0)
      }

    let VREFAdjustment: PostAdjustment? =
      if VREFAdditiveKts > 0 {
        PostAdjustment(
          kind: .VREFAdditive(.init(value: VREFAdditiveKts, unit: .knots)),
          factor: VREFFactor
        )
      } else {
        nil
      }

    let (finalRun, runAdjustments) = applyPostAdjustments(
      to: runValue,
      VREFAdjustment: VREFAdjustment,
      safetyFactor: safetyFactor
    )
    let (finalDist, distAdjustments) = applyPostAdjustments(
      to: distValue,
      VREFAdjustment: VREFAdjustment,
      safetyFactor: safetyFactor
    )

    let results = LandingResults(
      Vref: (model.VrefKts + VREFAdditiveKts).toMeasurement(UnitSpeed.knots),
      landingRun: finalRun.toMeasurement(UnitLength.feet),
      landingDistance: finalDist.toMeasurement(UnitLength.feet),
      meetsGoAroundClimbGradient: model.meetsGoAroundClimbGradient
    )

    return LandingReport(
      results: results,
      groundRunBreakdown: runBreakdown.appending(runAdjustments),
      distanceBreakdown: distBreakdown.appending(distAdjustments)
    )
  }
}

// MARK: - Post-Adjustment Helpers

extension DefaultPerformanceCalculationService {

  /// Applies optional VREF and safety adjustments to a base distance value,
  /// returning the final value and the adjustments for the breakdown.
  private func applyPostAdjustments(
    to baseValue: Value<Double>,
    VREFAdjustment: PostAdjustment? = nil,
    safetyFactor: Double
  ) -> (Value<Double>, [PerformanceAdjustment]) {
    var running = baseValue
    var adjustments: [PerformanceAdjustment] = []

    if let VREFAdjustment {
      running *= VREFAdjustment.factor
      adjustments.append(
        PerformanceAdjustment(
          kind: VREFAdjustment.kind,
          multiplier: VREFAdjustment.factor.nominal ?? 1.0,
          resultFt: running
        )
      )
    }

    if safetyFactor != 1.0 {
      running *= safetyFactor
      adjustments.append(
        PerformanceAdjustment(
          kind: .safetyMargin(safetyFactor),
          multiplier: safetyFactor,
          resultFt: running
        )
      )
    }

    return (running, adjustments)
  }

  /// A VREF or similar adjustment to apply before the safety factor.
  private struct PostAdjustment {
    let kind: AdjustmentKind
    let factor: Value<Double>
  }
}
