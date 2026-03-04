import Foundation

/// Base implementation of ``PerformanceModel`` with common functionality.
///
/// ``BasePerformanceModel`` provides shared infrastructure for performance calculations
/// including input data storage and common derived values (headwind, gradient, etc.).
///
/// ## Subclassing Notes
///
/// Distance properties (``takeoffRunFt``, ``takeoffDistanceFt``, ``landingRunFt``,
/// ``landingDistanceFt``) are computed via ``computeDistance(for:)`` and do not need
/// to be overridden. Instead, subclasses must override:
/// - ``baseValue(for:)`` - The unadjusted distance from equations or table lookup
/// - ``applyAdjustment(_:to:target:)`` - How to apply one adjustment using model-specific method
///
/// Non-distance properties must still be overridden:
/// - ``takeoffClimbGradientFtNM``
/// - ``takeoffClimbRateFtMin``
/// - ``VrefKts``
open class BasePerformanceModel: PerformanceModel {

  // MARK: - Properties

  public let conditions: Conditions
  public let configuration: Configuration
  public let runway: RunwayInput
  public let notam: NOTAMInput?

  // MARK: - Adjustment Generator

  var adjustmentGenerator: PerformanceAdjustmentGenerator {
    PerformanceAdjustmentGenerator(
      headwind: headwind,
      tailwind: tailwind,
      uphill: uphill,
      downhill: downhill,
      isTurf: runway.isTurf,
      contamination: notam?.contamination
    )
  }

  // MARK: - Distance Properties (computed via computeDistance)

  open var takeoffRunFt: Value<Double> {
    computeDistance(for: .takeoffRun).value
  }

  open var takeoffDistanceFt: Value<Double> {
    computeDistance(for: .takeoffDistance).value
  }

  open var landingRunFt: Value<Double> {
    computeDistance(for: .landingRun).value
  }

  open var landingDistanceFt: Value<Double> {
    computeDistance(for: .landingDistance).value
  }

  // MARK: - Non-Distance Properties (to be overridden)

  open var takeoffClimbGradientFtNM: Value<Double> {
    fatalError("Subclasses must implement takeoffClimbGradientFtNM")
  }

  open var takeoffClimbRateFtMin: Value<Double> {
    fatalError("Subclasses must implement takeoffClimbRateFtMin")
  }

  open var VrefKts: Value<Double> {
    fatalError("Subclasses must implement VrefKts")
  }

  open var meetsGoAroundClimbGradient: Value<Bool> {
    .notAvailable
  }

  open var enrouteClimbGradientFtNM: Value<Double> { .notAvailable }
  open var enrouteClimbRateFtMin: Value<Double> { .notAvailable }
  open var enrouteClimbSpeedKIAS: Value<Double> { .notAvailable }
  open var enrouteObstacleClimbGradientFtNM: Value<Double> { .notAvailable }
  open var enrouteObstacleClimbRateFtMin: Value<Double> { .notAvailable }

  open var takeoffInputsOffscaleLow: Bool { false }
  open var takeoffInputsOffscaleHigh: Bool { false }
  open var landingInputsOffscaleLow: Bool { false }
  open var landingInputsOffscaleHigh: Bool { false }

  // MARK: - Contamination Calculator

  /// Calculator for runway contamination effects. Set by subclass initializers.
  var contaminationCalculator: ContaminationCalculator?

  // MARK: - Common Input Properties

  /// Aircraft weight in pounds.
  var weight: Double {
    configuration.weight.converted(to: .pounds).value
  }

  /// Temperature in Celsius, or ISA if not reported.
  var temperature: Double {
    conditions.temperature?.converted(to: .celsius).value ?? isaTemperature(altitudeFt: altitude)
  }

  /// Runway elevation in feet.
  var altitude: Double {
    runway.elevation.converted(to: .feet).value
  }

  /// Headwind component in knots (positive = headwind, negative = tailwind).
  var headwindComponent: Double {
    runway.headwind(conditions: conditions).converted(to: .knots).value
  }

  /// Headwind in knots (zero if tailwind).
  var headwind: Double {
    headwindComponent > 0 ? headwindComponent : 0
  }

  /// Tailwind in knots (zero if headwind).
  var tailwind: Double {
    headwindComponent < 0 ? -headwindComponent : 0
  }

  /// Runway gradient as a fraction (positive = uphill).
  var gradient: Double {
    Double(runway.gradient)
  }

  /// Uphill gradient (zero if downhill).
  var uphill: Double {
    gradient > 0 ? gradient : 0
  }

  /// Downhill gradient as positive value (zero if uphill).
  var downhill: Double {
    gradient < 0 ? -gradient : 0
  }

  // MARK: - Initializer

  /**
   * Creates a base performance model with the given inputs.
   *
   * - Parameters:
   *   - conditions: Atmospheric conditions for the calculation.
   *   - configuration: Aircraft weight and flap configuration.
   *   - runway: Runway data snapshot.
   *   - notam: Active NOTAM restrictions, if any.
   */
  public init(
    conditions: Conditions,
    configuration: Configuration,
    runway: RunwayInput,
    notam: NOTAMInput?
  ) {
    self.conditions = conditions
    self.configuration = configuration
    self.runway = runway
    self.notam = notam
  }

  // MARK: - Distance Computation

  /// Computes the adjusted distance and breakdown for a given target.
  ///
  /// This method calls ``baseValue(for:)`` to get the unadjusted distance, then
  /// iterates through all applicable adjustments (determined by the adjustment generator),
  /// calling ``applyAdjustment(_:to:target:)`` for each one.
  open func computeDistance(for target: DistanceTarget)
    -> (value: Value<Double>, breakdown: DistanceBreakdown)
  {
    var value = baseValue(for: target)
    let baseFt = value
    var adjustments: [PerformanceAdjustment] = []

    for kind in adjustmentGenerator.adjustmentKinds(for: target) {
      let (newValue, multiplier) = applyAdjustment(kind, to: value, target: target)
      value = newValue
      adjustments.append(.init(kind: kind, multiplier: multiplier, resultFt: value))
    }

    return (value, .init(baseFt: baseFt, adjustments: adjustments))
  }

  /// Returns the base (unadjusted) distance for the given target.
  ///
  /// Subclasses must override this to provide the value from regression equations or table lookup.
  open func baseValue(for target: DistanceTarget) -> Value<Double> {
    assertionFailure("\(Self.self) must override baseValue(for: \(target))")
    return .notAvailable
  }

  /// Applies a single adjustment to a distance value.
  ///
  /// The default implementation routes contamination to ``applyContamination(_:to:target:)``
  /// and all other adjustments through ``adjustmentMultiplier(for:target:)``.
  open func applyAdjustment(
    _ kind: AdjustmentKind,
    to value: Value<Double>,
    target: DistanceTarget
  ) -> (result: Value<Double>, effectiveMultiplier: Double) {
    switch kind {
      case .contamination(let contamination):
        return applyContamination(contamination, to: value, target: target)
      default:
        let multiplier = adjustmentMultiplier(for: kind, target: target)
        var result = value
        result *= multiplier
        return (result, multiplier.nominal ?? 1.0)
    }
  }

  /// Returns the multiplicative adjustment factor for a given adjustment kind and target.
  ///
  /// Subclasses must override this to provide model-specific factors. Regression models
  /// return scalar factors wrapped in `.value()`, while tabular models return factors
  /// interpolated from data tables.
  open func adjustmentMultiplier(
    for kind: AdjustmentKind,
    target: DistanceTarget
  ) -> Value<Double> {
    assertionFailure(
      "\(Self.self) must override adjustmentMultiplier(for: \(kind), target: \(target))"
    )
    return .value(1.0)
  }

  /// Applies a contamination adjustment to a distance value.
  ///
  /// Uses the contamination calculator for additive contamination effects
  /// on landing distances.
  open func applyContamination(
    _ contamination: Contamination,
    to value: Value<Double>,
    target: DistanceTarget
  ) -> (result: Value<Double>, effectiveMultiplier: Double) {
    guard let contaminationCalculator else {
      return (value, 1.0)
    }
    let newValue: Value<Double>
    switch target {
      case .landingRun:
        newValue = contaminationCalculator.landingRunContaminationAddition(
          distance: value,
          contamination: contamination,
          isGroovedOrPFC: runway.isGroovedOrPFC
        )
      case .landingDistance:
        newValue = contaminationCalculator.landingDistanceContaminationAddition(
          landingDistance: value,
          landingRun: baseValue(for: .landingRun),
          contamination: contamination,
          isGroovedOrPFC: runway.isGroovedOrPFC
        )
      default:
        return (value, 1.0)
    }
    return (newValue, effectiveMultiplier(from: value, to: newValue))
  }

  /// Computes the effective multiplier between two values.
  func effectiveMultiplier(from oldValue: Value<Double>, to newValue: Value<Double>) -> Double {
    guard let old = oldValue.nominal, old > 0, let new = newValue.nominal else {
      return 1.0
    }
    return new / old
  }
}
