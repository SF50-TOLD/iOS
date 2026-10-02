import Foundation

/// Unified tabular performance model for all SF50 Vision Jet variants.
///
/// ``TabularPerformanceModel`` calculates takeoff and landing performance using
/// direct interpolation from digitized AFM table data. The `aircraftType` parameter
/// drives which data files are loaded and determines vref loading behavior.
final class TabularPerformanceModel: BasePerformanceModel {

  // MARK: - Properties

  private static let seaLevelFt = 0.0

  private let limitations: any Limitations.Type
  private let takeoffRunData: DataTable
  private let takeoffDistanceData: DataTable
  private let takeoffClimbGradientData: DataTable
  private let takeoffClimbRateData: DataTable
  private let vrefData: DataTable
  private let landingRunData: DataTable
  private let landingDistanceData: DataTable

  private let takeoffRun_headwindData: DataTable
  private let takeoffRun_tailwindData: DataTable
  private let takeoffRun_downhillData: DataTable
  private let takeoffRun_uphillData: DataTable
  private let takeoffDistance_headwindData: DataTable
  private let takeoffDistance_tailwindData: DataTable
  private let takeoffDistance_unpavedData: DataTable

  private let landingRun_headwindData: DataTable
  private let landingRun_tailwindData: DataTable
  private let landingRun_downhillData: DataTable
  private let landingRun_uphillData: DataTable
  private let landingDistance_headwindData: DataTable
  private let landingDistance_tailwindData: DataTable
  private let landingDistance_unpavedData: DataTable

  private let enrouteClimb_gradientNormalData: DataTable
  private let enrouteClimb_rateNormalData: DataTable
  private let enrouteClimb_speedNormalData: DataTable
  private let enrouteClimb_gradientIceContaminatedData: DataTable
  private let enrouteClimb_rateIceContaminatedData: DataTable
  private let enrouteClimb_speedIceContaminatedData: DataTable

  // MARK: - Non-Distance Outputs

  override var takeoffClimbGradientFtNM: Value<Double> {
    atApprovedAirport { takeoffClimbGradientData.value(for: [weight, chartElevation, temperature]) }
  }

  override var takeoffClimbRateFtMin: Value<Double> {
    atApprovedAirport { takeoffClimbRateData.value(for: [weight, chartElevation, temperature]) }
  }

  override var VrefKts: Value<Double> {
    vrefData.value(for: [weight])
  }

  /// Whether the AFM's go-around climb gradient is met.
  ///
  /// The tables publish a landing distance only where the gradient is met, so a distance the model
  /// can stand behind answers yes and one off the top of the tables answers no. Where the model has
  /// no distance at all it has no answer either, and says so rather than assuming the gradient
  /// holds.
  override var meetsGoAroundClimbGradient: Value<Bool> {
    switch landingDistanceFt {
      case .value, .valueWithUncertainty: .value(true)
      case .offscaleHigh: .value(false)
      case .offscaleLow(let clamped): clamped == nil ? .notAvailable : .value(true)
      case .invalid: .invalid
      case .notAvailable: .notAvailable
      case .notAuthorized: .notAuthorized
    }
  }

  // MARK: - En Route Climb

  override var enrouteClimbGradientFtNM: Value<Double> {
    let data =
      configuration.iceProtection
      ? enrouteClimb_gradientIceContaminatedData : enrouteClimb_gradientNormalData
    return data.value(for: [altitude, temperature, weight])
  }

  override var enrouteClimbRateFtMin: Value<Double> {
    let data =
      configuration.iceProtection
      ? enrouteClimb_rateIceContaminatedData : enrouteClimb_rateNormalData
    return data.value(for: [altitude, temperature, weight])
  }

  override var enrouteClimbSpeedKIAS: Value<Double> {
    let data =
      configuration.iceProtection
      ? enrouteClimb_speedIceContaminatedData : enrouteClimb_speedNormalData
    return data.value(for: [altitude, temperature, weight])
  }

  // MARK: - Initializer

  init(
    conditions: Conditions,
    configuration: Configuration,
    runway: RunwayInput,
    notam: NOTAMInput?,
    aircraftType: AircraftType
  ) {
    let loader = DataTableLoader(aircraftType: aircraftType)
    let landingPrefix = loader.landingPrefix(for: configuration.flapSetting)

    limitations = aircraftType.limitations

    takeoffRunData = loader.loadTakeoffRunData()
    takeoffDistanceData = loader.loadTakeoffDistanceData()
    takeoffClimbGradientData = loader.loadTakeoffClimbGradientData()
    takeoffClimbRateData = loader.loadTakeoffClimbRateData()

    vrefData = loader.loadVrefData(vrefPrefix: loader.vrefPrefix(for: configuration.flapSetting))

    landingRunData = loader.loadLandingRunData(landingPrefix: landingPrefix)
    landingDistanceData = loader.loadLandingDistanceData(landingPrefix: landingPrefix)

    takeoffRun_headwindData = loader.loadTakeoffRunHeadwindData()
    takeoffRun_tailwindData = loader.loadTakeoffRunTailwindData()
    takeoffRun_downhillData = loader.loadTakeoffRunDownhillData()
    takeoffRun_uphillData = loader.loadTakeoffRunUphillData()
    takeoffDistance_headwindData = loader.loadTakeoffDistanceHeadwindData()
    takeoffDistance_tailwindData = loader.loadTakeoffDistanceTailwindData()
    takeoffDistance_unpavedData = loader.loadTakeoffDistanceUnpavedData()

    landingRun_headwindData = loader.loadLandingRunHeadwindData(landingPrefix: landingPrefix)
    landingRun_tailwindData = loader.loadLandingRunTailwindData(landingPrefix: landingPrefix)
    landingRun_downhillData = loader.loadLandingRunDownhillData(landingPrefix: landingPrefix)
    landingRun_uphillData = loader.loadLandingRunUphillData(landingPrefix: landingPrefix)
    landingDistance_headwindData = loader.loadLandingDistanceHeadwindData(
      landingPrefix: landingPrefix
    )
    landingDistance_tailwindData = loader.loadLandingDistanceTailwindData(
      landingPrefix: landingPrefix
    )
    landingDistance_unpavedData = loader.loadLandingDistanceUnpavedData(
      landingPrefix: landingPrefix
    )

    enrouteClimb_gradientNormalData = loader.loadEnrouteClimbGradientData(iceContaminated: false)
    enrouteClimb_rateNormalData = loader.loadEnrouteClimbRateData(iceContaminated: false)
    enrouteClimb_speedNormalData = loader.loadEnrouteClimbSpeedData(iceContaminated: false)
    enrouteClimb_gradientIceContaminatedData = loader.loadEnrouteClimbGradientData(
      iceContaminated: true
    )
    enrouteClimb_rateIceContaminatedData = loader.loadEnrouteClimbRateData(iceContaminated: true)
    enrouteClimb_speedIceContaminatedData = loader.loadEnrouteClimbSpeedData(
      iceContaminated: true
    )

    super.init(conditions: conditions, configuration: configuration, runway: runway, notam: notam)
    contaminationCalculator = ContaminationCalculator(loader: loader)
  }

  // MARK: - Base Values

  /// The AFM's distance for the current conditions, before any adjustment.
  ///
  /// Distance grows with weight, altitude and temperature alike, so an input below the tabulated
  /// range is held at the bottom of it: the figure that comes back is longer than the truth, which
  /// is the side to err on. It comes back as a clamped offscale figure rather than a definite one,
  /// so that the readout can say the AFM never covered the conditions asked for. Above the range,
  /// where holding the input would understate the distance, no figure is offered at all.
  override func baseValue(for target: DistanceTarget) -> Value<Double> {
    atApprovedAirport {
      switch target {
        case .takeoffRun:
          takeoffRunData.value(
            for: [weight, chartElevation, temperature],
            clamping: [.clampLow, .clampLow, .clampLow]
          )
        case .takeoffDistance:
          takeoffDistanceData.value(
            for: [weight, chartElevation, temperature],
            clamping: [.clampLow, .clampLow, .clampLow]
          )
        case .landingRun:
          configuration.flapSetting.hasLandingGroundRun
            ? landingRunData.value(
              for: [weight, chartElevation, temperature],
              clamping: [.clampLow, .clampLow, .clampLow]
            )
            : .notAvailable
        case .landingDistance:
          landingDistanceData.value(
            for: [weight, chartElevation, temperature],
            clamping: [.clampLow, .clampLow, .clampLow]
          ) * (configuration.flapSetting.flapsUpLandingDistanceFactor ?? 1)
      }
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
        PerformanceAdjustments.windAdjustment(
          factor: lookupFactor(takeoffRun_headwindData),
          wind: -headwind
        )
      case (.tailwind, .takeoffRun):
        PerformanceAdjustments.windAdjustment(
          factor: lookupFactor(takeoffRun_tailwindData),
          wind: tailwind
        )
      case (.uphillGradient, .takeoffRun):
        PerformanceAdjustments.gradientAdjustment(
          factor: lookupFactor(takeoffRun_uphillData),
          gradient: uphill
        )
      case (.downhillGradient, .takeoffRun):
        PerformanceAdjustments.gradientAdjustment(
          factor: lookupFactor(takeoffRun_downhillData),
          gradient: -downhill
        )

      // Takeoff Distance
      case (.headwind, .takeoffDistance):
        PerformanceAdjustments.windAdjustment(
          factor: lookupFactor(takeoffDistance_headwindData),
          wind: -headwind
        )
      case (.tailwind, .takeoffDistance):
        PerformanceAdjustments.windAdjustment(
          factor: lookupFactor(takeoffDistance_tailwindData),
          wind: tailwind
        )
      case (.unpavedSurface, .takeoffDistance):
        PerformanceAdjustments.surfaceAdjustment(
          factor: lookupFactor(takeoffDistance_unpavedData)
        )

      // Landing Run
      case (.headwind, .landingRun):
        PerformanceAdjustments.windAdjustment(
          factor: lookupFactor(landingRun_headwindData),
          wind: -headwind
        )
      case (.tailwind, .landingRun):
        PerformanceAdjustments.windAdjustment(
          factor: lookupFactor(landingRun_tailwindData),
          wind: tailwind
        )
      case (.uphillGradient, .landingRun):
        PerformanceAdjustments.gradientAdjustment(
          factor: lookupFactor(landingRun_uphillData),
          gradient: -uphill
        )
      case (.downhillGradient, .landingRun):
        PerformanceAdjustments.gradientAdjustment(
          factor: lookupFactor(landingRun_downhillData),
          gradient: downhill
        )

      // Landing Distance
      case (.headwind, .landingDistance):
        PerformanceAdjustments.windAdjustment(
          factor: lookupFactor(landingDistance_headwindData),
          wind: -headwind
        )
      case (.tailwind, .landingDistance):
        PerformanceAdjustments.windAdjustment(
          factor: lookupFactor(landingDistance_tailwindData),
          wind: tailwind
        )
      case (.unpavedSurface, .landingDistance):
        PerformanceAdjustments.surfaceAdjustment(
          factor: lookupFactor(landingDistance_unpavedData)
        )

      default:
        fatalError("Unexpected adjustment \(kind) for target \(target)")
    }
  }

  /// Looks up a weight-dependent adjustment factor from a data table.
  ///
  /// These factors grow with weight, so holding a light aircraft at the lightest tabulated weight
  /// overstates the penalty and the answer stays on the safe side. A weight above the heaviest
  /// tabulated one would have its penalty understated, so it comes back offscale instead.
  private func lookupFactor(_ data: DataTable) -> Value<Double> {
    data.value(for: [weight], clamping: [.clampLow])
  }
}

// MARK: - Airport Elevation

extension TabularPerformanceModel {
  /// Whether the airport lies within the elevations the AFM approves for takeoff and landing.
  ///
  /// The tables answer only there; the regression model is free to extrapolate past them.
  private var isAirportElevationApproved: Bool {
    (limitations.minAirportElevation...limitations.maxAirportElevation).contains(runway.elevation)
  }

  /// The elevation the takeoff and landing tables are read at.
  ///
  /// Below sea level the AFM has its sea-level figures used, so those are what the tables give,
  /// as an answer the AFM stands behind rather than an offscale one.
  private var chartElevation: Double {
    Swift.max(altitude, Self.seaLevelFt)
  }

  /// Reads a takeoff or landing figure, which the AFM does not authorize at an airport outside its
  /// approved elevations.
  private func atApprovedAirport(_ figure: () -> Value<Double>) -> Value<Double> {
    isAirportElevationApproved ? figure() : .notAuthorized
  }
}
