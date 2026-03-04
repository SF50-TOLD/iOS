import Foundation

/// Unified tabular performance model for all SF50 Vision Jet variants.
///
/// ``TabularPerformanceModel`` calculates takeoff and landing performance using
/// direct interpolation from digitized AFM table data. The `aircraftType` parameter
/// drives which data files are loaded and determines vref loading behavior.
final class TabularPerformanceModel: BasePerformanceModel {

  // MARK: - Properties

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
    takeoffClimbGradientData.value(for: [weight, altitude, temperature])
  }

  override var takeoffClimbRateFtMin: Value<Double> {
    takeoffClimbRateData.value(for: [weight, altitude, temperature])
  }

  override var VrefKts: Value<Double> {
    vrefData.value(for: [weight])
  }

  override var meetsGoAroundClimbGradient: Value<Bool> {
    switch landingDistanceFt {
      case .notAvailable: .notAvailable
      case .notAuthorized: .notAuthorized
      case .offscaleHigh: .value(false)
      default: .value(true)
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

    takeoffRunData = loader.loadTakeoffRunData()
    takeoffDistanceData = loader.loadTakeoffDistanceData()
    takeoffClimbGradientData = loader.loadTakeoffClimbGradientData()
    takeoffClimbRateData = loader.loadTakeoffClimbRateData()

    // G2+ uses unprefixed vref data; G1/G2 use flap-specific prefixed data
    switch aircraftType {
      case .g2Plus, .g2(updatedThrustSchedule: true):
        vrefData = loader.loadVrefData()
      default:
        vrefData = loader.loadVrefData(
          vrefPrefix: loader.vrefPrefix(for: configuration.flapSetting)
        )
    }

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
    contaminationCalculator = ContaminationCalculator(
      aircraftType: aircraftType,
      loader: loader
    )
  }

  // MARK: - Base Values

  override func baseValue(for target: DistanceTarget) -> Value<Double> {
    switch target {
      case .takeoffRun:
        takeoffRunData.value(
          for: [weight, altitude, temperature],
          clamping: [.clampLow, .clampLow, .clampLow]
        )
      case .takeoffDistance:
        takeoffDistanceData.value(
          for: [weight, altitude, temperature],
          clamping: [.clampLow, .clampLow, .clampLow]
        )
      case .landingRun:
        landingRunData.value(
          for: [weight, altitude, temperature],
          clamping: [.clampLow, .clampLow, .clampLow]
        )
      case .landingDistance:
        landingDistanceData.value(
          for: [weight, altitude, temperature],
          clamping: [.clampLow, .clampLow, .clampLow]
        )
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
  private func lookupFactor(_ data: DataTable) -> Value<Double> {
    data.value(for: [weight], clamping: [.clampBoth])
  }
}
