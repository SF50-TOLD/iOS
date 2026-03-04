import Foundation

/// Unified regression-based performance model for all SF50 Vision Jet variants.
///
/// ``RegressionPerformanceModel`` calculates takeoff and landing performance using
/// polynomial regression equations derived from AFM table data. The `aircraftType`
/// parameter drives which JSON data files get loaded (via the
/// ``RegressionEquationLoader``), selecting the appropriate coefficients and
/// adjustment factors for each variant.
///
/// ## Bounds Checking
///
/// Regression models can extrapolate beyond the original AFM data range, but results
/// outside the bounds may be less reliable. Input ranges are validated against
/// the tabular model limits via ``BoundsChecker``.
final class RegressionPerformanceModel: BasePerformanceModel {

  // MARK: - Stored Properties

  private let boundsChecker: BoundsChecker

  // Takeoff
  private let takeoffRunEquation: RegressionEquation
  private let takeoffDistanceEquation: RegressionEquation
  private let takeoffClimbGradientEquation: RegressionEquation
  private let takeoffClimbRateEquation: RegressionEquation

  // En Route Climb
  private let enrouteClimbGradientNormalEquation: RegressionEquation
  private let enrouteClimbRateNormalEquation: RegressionEquation
  private let enrouteClimbSpeedNormalEquation: RegressionEquation
  private let enrouteClimbGradientIceEquation: RegressionEquation
  private let enrouteClimbRateIceEquation: RegressionEquation
  private let enrouteClimbSpeedIceEquation: RegressionEquation

  // En Route Obstacle Climb
  private let enrouteObstacleClimbGradientNormalEquation: RegressionEquation
  private let enrouteObstacleClimbRateNormalEquation: RegressionEquation
  private let enrouteObstacleClimbGradientIceEquation: RegressionEquation
  private let enrouteObstacleClimbRateIceEquation: RegressionEquation

  // Landing
  private let landingRunFlaps100Equation: RegressionEquation
  private let landingRunFlaps50Equation: RegressionEquation
  private let landingRunFlaps50IceEquation: RegressionEquation
  private let landingDistanceFlaps100Equation: RegressionEquation
  private let landingDistanceFlaps50Equation: RegressionEquation
  private let landingDistanceFlaps50IceEquation: RegressionEquation

  // Go-Around
  private let goAroundEquation: RegressionEquation

  // VREF
  private let vrefEquation: RegressionEquation

  // Takeoff Adjustment Factors
  private let takeoffRunHeadwindFactorEquation: RegressionEquation,
    takeoffRunTailwindFactorEquation: RegressionEquation,
    takeoffRunUphillFactorEquation: RegressionEquation,
    takeoffRunDownhillFactorEquation: RegressionEquation,
    takeoffDistanceHeadwindFactorEquation: RegressionEquation,
    takeoffDistanceTailwindFactorEquation: RegressionEquation,
    takeoffDistanceUnpavedFactorEquation: RegressionEquation

  // Landing Adjustment Factors
  private let landingRunHeadwindFactorEquation: RegressionEquation,
    landingRunTailwindFactorEquation: RegressionEquation,
    landingRunUphillFactorEquation: RegressionEquation,
    landingRunDownhillFactorEquation: RegressionEquation,
    landingDistanceHeadwindFactorEquation: RegressionEquation,
    landingDistanceTailwindFactorEquation: RegressionEquation,
    landingDistanceUnpavedFactorEquation: RegressionEquation

  // MARK: - Bounds Checking

  override var takeoffInputsOffscaleLow: Bool {
    boundsChecker.takeoffBoundsStatus(
      weight: weight,
      altitude: altitude,
      temperature: temperature
    ) == .belowMinimum
  }

  override var takeoffInputsOffscaleHigh: Bool {
    boundsChecker.takeoffBoundsStatus(
      weight: weight,
      altitude: altitude,
      temperature: temperature
    ) == .aboveMaximum
  }

  override var landingInputsOffscaleLow: Bool {
    boundsChecker.landingBoundsStatus(
      weight: weight,
      altitude: altitude,
      temperature: temperature,
      flapSetting: configuration.flapSetting
    ) == .belowMinimum
  }

  override var landingInputsOffscaleHigh: Bool {
    boundsChecker.landingBoundsStatus(
      weight: weight,
      altitude: altitude,
      temperature: temperature,
      flapSetting: configuration.flapSetting
    ) == .aboveMaximum
  }

  // MARK: - VREF

  override var VrefKts: Value<Double> {
    evaluate(vrefEquation)
  }

  // MARK: - Takeoff Climb

  override var takeoffClimbGradientFtNM: Value<Double> {
    evaluate(takeoffClimbGradientEquation)
  }

  override var takeoffClimbRateFtMin: Value<Double> {
    evaluate(takeoffClimbRateEquation)
  }

  // MARK: - En Route Climb

  override var enrouteClimbGradientFtNM: Value<Double> {
    configuration.iceProtection
      ? evaluate(enrouteClimbGradientIceEquation)
      : evaluate(enrouteClimbGradientNormalEquation)
  }

  override var enrouteClimbRateFtMin: Value<Double> {
    configuration.iceProtection
      ? evaluate(enrouteClimbRateIceEquation)
      : evaluate(enrouteClimbRateNormalEquation)
  }

  override var enrouteClimbSpeedKIAS: Value<Double> {
    configuration.iceProtection
      ? evaluate(enrouteClimbSpeedIceEquation)
      : evaluate(enrouteClimbSpeedNormalEquation)
  }

  // MARK: - En Route Obstacle Climb

  override var enrouteObstacleClimbGradientFtNM: Value<Double> {
    configuration.iceProtection
      ? evaluateDelta(
        base: enrouteObstacleClimbGradientNormalEquation,
        delta: enrouteObstacleClimbGradientIceEquation
      )
      : evaluate(enrouteObstacleClimbGradientNormalEquation)
  }

  override var enrouteObstacleClimbRateFtMin: Value<Double> {
    configuration.iceProtection
      ? evaluateDelta(
        base: enrouteObstacleClimbRateNormalEquation,
        delta: enrouteObstacleClimbRateIceEquation
      )
      : evaluate(enrouteObstacleClimbRateNormalEquation)
  }

  // MARK: - Go-Around Climb Gradient

  override var meetsGoAroundClimbGradient: Value<Bool> {
    evaluateBool(goAroundEquation)
  }

  // MARK: - Landing Base Values

  private var landingRunBaseFt: Value<Double> {
    switch configuration.flapSetting {
      case .flaps100: evaluate(landingRunFlaps100Equation)
      case .flaps50, .flapsUp: evaluate(landingRunFlaps50Equation)
      case .flaps50Ice, .flapsUpIce: evaluate(landingRunFlaps50IceEquation)
    }
  }

  private var landingDistanceBaseFt: Value<Double> {
    switch configuration.flapSetting {
      case .flaps100: evaluate(landingDistanceFlaps100Equation)
      case .flaps50: evaluate(landingDistanceFlaps50Equation)
      case .flaps50Ice: evaluate(landingDistanceFlaps50IceEquation)
      case .flapsUp: evaluate(landingDistanceFlaps50Equation) * 1.38
      case .flapsUpIce: evaluate(landingDistanceFlaps50IceEquation) * 1.52
    }
  }

  // MARK: - Initializer

  init(
    conditions: Conditions,
    configuration: Configuration,
    runway: RunwayInput,
    notam: NOTAMInput?,
    aircraftType: AircraftType
  ) {
    self.boundsChecker = BoundsChecker(aircraftType: aircraftType)

    let loader = RegressionEquationLoader(aircraftType: aircraftType)

    takeoffRunEquation = loader.loadTakeoffRunEquation()
    takeoffDistanceEquation = loader.loadTakeoffDistanceEquation()
    takeoffClimbGradientEquation = loader.loadTakeoffClimbGradientEquation()
    takeoffClimbRateEquation = loader.loadTakeoffClimbRateEquation()

    enrouteClimbGradientNormalEquation = loader.loadEnrouteClimbGradientEquation(
      iceContaminated: false
    )
    enrouteClimbRateNormalEquation = loader.loadEnrouteClimbRateEquation(iceContaminated: false)
    enrouteClimbSpeedNormalEquation = loader.loadEnrouteClimbSpeedEquation(iceContaminated: false)
    enrouteClimbGradientIceEquation = loader.loadEnrouteClimbGradientEquation(
      iceContaminated: true
    )
    enrouteClimbRateIceEquation = loader.loadEnrouteClimbRateEquation(iceContaminated: true)
    enrouteClimbSpeedIceEquation = loader.loadEnrouteClimbSpeedEquation(iceContaminated: true)

    enrouteObstacleClimbGradientNormalEquation =
      loader.loadEnrouteObstacleClimbGradientEquation(iceContaminated: false)
    enrouteObstacleClimbRateNormalEquation = loader.loadEnrouteObstacleClimbRateEquation(
      iceContaminated: false
    )
    enrouteObstacleClimbGradientIceEquation = loader.loadEnrouteObstacleClimbGradientEquation(
      iceContaminated: true
    )
    enrouteObstacleClimbRateIceEquation = loader.loadEnrouteObstacleClimbRateEquation(
      iceContaminated: true
    )

    landingRunFlaps100Equation = loader.loadLandingRunEquation(flapSetting: .flaps100)
    landingRunFlaps50Equation = loader.loadLandingRunEquation(flapSetting: .flaps50)
    landingRunFlaps50IceEquation = loader.loadLandingRunEquation(flapSetting: .flaps50Ice)
    landingDistanceFlaps100Equation = loader.loadLandingDistanceEquation(flapSetting: .flaps100)
    landingDistanceFlaps50Equation = loader.loadLandingDistanceEquation(flapSetting: .flaps50)
    landingDistanceFlaps50IceEquation = loader.loadLandingDistanceEquation(
      flapSetting: .flaps50Ice
    )

    goAroundEquation = loader.loadGoAroundClimbGradientEquation()
    vrefEquation = loader.loadVrefEquation(flapSetting: configuration.flapSetting)

    takeoffRunHeadwindFactorEquation = loader.loadTakeoffRunHeadwindFactorEquation()
    takeoffRunTailwindFactorEquation = loader.loadTakeoffRunTailwindFactorEquation()
    takeoffRunUphillFactorEquation = loader.loadTakeoffRunUphillFactorEquation()
    takeoffRunDownhillFactorEquation = loader.loadTakeoffRunDownhillFactorEquation()
    takeoffDistanceHeadwindFactorEquation = loader.loadTakeoffDistanceHeadwindFactorEquation()
    takeoffDistanceTailwindFactorEquation = loader.loadTakeoffDistanceTailwindFactorEquation()
    takeoffDistanceUnpavedFactorEquation = loader.loadTakeoffDistanceUnpavedFactorEquation()

    let landingFlapSetting = configuration.flapSetting.landingFactorFlapSetting
    landingRunHeadwindFactorEquation = loader.loadLandingRunHeadwindFactorEquation(
      flapSetting: landingFlapSetting
    )
    landingRunTailwindFactorEquation = loader.loadLandingRunTailwindFactorEquation(
      flapSetting: landingFlapSetting
    )
    landingRunUphillFactorEquation = loader.loadLandingRunUphillFactorEquation(
      flapSetting: landingFlapSetting
    )
    landingRunDownhillFactorEquation = loader.loadLandingRunDownhillFactorEquation()
    landingDistanceHeadwindFactorEquation = loader.loadLandingDistanceHeadwindFactorEquation(
      flapSetting: landingFlapSetting
    )
    landingDistanceTailwindFactorEquation = loader.loadLandingDistanceTailwindFactorEquation(
      flapSetting: landingFlapSetting
    )
    landingDistanceUnpavedFactorEquation = loader.loadLandingDistanceUnpavedFactorEquation()

    super.init(conditions: conditions, configuration: configuration, runway: runway, notam: notam)
    contaminationCalculator = ContaminationCalculator(aircraftType: aircraftType)
  }

  // MARK: - Base Values

  override func baseValue(for target: DistanceTarget) -> Value<Double> {
    switch target {
      case .takeoffRun: evaluate(takeoffRunEquation)
      case .takeoffDistance: evaluate(takeoffDistanceEquation)
      case .landingRun: landingRunBaseFt
      case .landingDistance: landingDistanceBaseFt
    }
  }

  // MARK: - Adjustment Multiplier

  override func adjustmentMultiplier(
    for kind: AdjustmentKind,
    target: DistanceTarget
  ) -> Value<Double> {
    switch (kind, target) {
      // Takeoff Run
      case (.headwind, .takeoffRun):
        .value(
          PerformanceAdjustments.windAdjustment(
            factor: evaluateFactor(takeoffRunHeadwindFactorEquation),
            wind: -headwind
          )
        )
      case (.tailwind, .takeoffRun):
        .value(
          PerformanceAdjustments.windAdjustment(
            factor: evaluateFactor(takeoffRunTailwindFactorEquation),
            wind: tailwind
          )
        )
      case (.uphillGradient, .takeoffRun):
        .value(
          PerformanceAdjustments.gradientAdjustment(
            factor: evaluateFactor(takeoffRunUphillFactorEquation),
            gradient: uphill
          )
        )
      case (.downhillGradient, .takeoffRun):
        .value(
          PerformanceAdjustments.gradientAdjustment(
            factor: evaluateFactor(takeoffRunDownhillFactorEquation),
            gradient: -downhill
          )
        )

      // Takeoff Distance
      case (.headwind, .takeoffDistance):
        .value(
          PerformanceAdjustments.windAdjustment(
            factor: evaluateFactor(takeoffDistanceHeadwindFactorEquation),
            wind: -headwind
          )
        )
      case (.tailwind, .takeoffDistance):
        .value(
          PerformanceAdjustments.windAdjustment(
            factor: evaluateFactor(takeoffDistanceTailwindFactorEquation),
            wind: tailwind
          )
        )
      case (.unpavedSurface, .takeoffDistance):
        .value(
          PerformanceAdjustments.surfaceAdjustment(
            factor: evaluateFactor(takeoffDistanceUnpavedFactorEquation)
          )
        )

      // Landing Run
      case (.headwind, .landingRun):
        .value(
          PerformanceAdjustments.windAdjustment(
            factor: evaluateFactor(landingRunHeadwindFactorEquation),
            wind: -headwind
          )
        )
      case (.tailwind, .landingRun):
        .value(
          PerformanceAdjustments.windAdjustment(
            factor: evaluateFactor(landingRunTailwindFactorEquation),
            wind: tailwind
          )
        )
      case (.uphillGradient, .landingRun):
        .value(
          PerformanceAdjustments.gradientAdjustment(
            factor: evaluateFactor(landingRunUphillFactorEquation),
            gradient: -uphill
          )
        )
      case (.downhillGradient, .landingRun):
        .value(
          PerformanceAdjustments.gradientAdjustment(
            factor: evaluateFactor(landingRunDownhillFactorEquation),
            gradient: downhill
          )
        )

      // Landing Distance
      case (.headwind, .landingDistance):
        .value(
          PerformanceAdjustments.windAdjustment(
            factor: evaluateFactor(landingDistanceHeadwindFactorEquation),
            wind: -headwind
          )
        )
      case (.tailwind, .landingDistance):
        .value(
          PerformanceAdjustments.windAdjustment(
            factor: evaluateFactor(landingDistanceTailwindFactorEquation),
            wind: tailwind
          )
        )
      case (.unpavedSurface, .landingDistance):
        .value(
          PerformanceAdjustments.surfaceAdjustment(
            factor: evaluateFactor(landingDistanceUnpavedFactorEquation)
          )
        )

      default:
        fatalError("Unexpected adjustment \(kind) for target \(target)")
    }
  }
}

// MARK: - Equation Evaluation

extension RegressionPerformanceModel {

  /// Evaluates a factor equation and returns its raw numeric value.
  private func evaluateFactor(_ equation: RegressionEquation) -> Double {
    guard let value = evaluate(equation).nominal else {
      preconditionFailure("Factor equation returned invalid result")
    }
    return value
  }

  /// Evaluates a regression equation with the current input conditions.
  func evaluate(_ equation: RegressionEquation) -> Value<Double> {
    equation.evaluate(inputs: [
      "weight": weight,
      "altitude": altitude,
      "temperature": temperature
    ])
  }

  /// Evaluates a logistic equation with the current input conditions.
  func evaluateBool(_ equation: RegressionEquation) -> Value<Bool> {
    equation.evaluateBool(inputs: [
      "weight": weight,
      "altitude": altitude,
      "temperature": temperature
    ])
  }

  /// Evaluates a delta equation: result = base_value - max(0, delta_value).
  ///
  /// Falls back to regular evaluation if the equation is not a delta type.
  func evaluateDelta(base: RegressionEquation, delta: RegressionEquation) -> Value<Double> {
    guard delta.type == .deltaPolynomial else {
      return evaluate(delta)
    }

    let inputs: [String: Double] = [
      "weight": weight,
      "altitude": altitude,
      "temperature": temperature
    ]

    let baseResult = base.evaluate(inputs: inputs)
    let deltaResult = delta.evaluate(inputs: inputs)

    let baseVal: Double
    switch baseResult {
      case .value(let v): baseVal = v
      case .valueWithUncertainty(let v, _): baseVal = v
      default: return evaluate(delta)
    }

    let deltaVal: Double
    switch deltaResult {
      case .value(let v): deltaVal = v
      case .valueWithUncertainty(let v, _): deltaVal = v
      default: return evaluate(delta)
    }

    let result = baseVal - max(0, deltaVal)

    if let key = delta.uncertaintyKey {
      let rmse = ResidualErrorCalculator.RMSE(for: key, binParameters: inputs)
      return .valueWithUncertainty(result, uncertainty: rmse)
    }
    return .value(result)
  }

  /// Returns the RMSE uncertainty for a specific calculation table.
  func uncertainty(for table: String) -> Double {
    ResidualErrorCalculator.RMSE(
      for: table,
      binParameters: [
        "weight": weight,
        "altitude": altitude,
        "temperature": temperature
      ]
    )
  }
}
