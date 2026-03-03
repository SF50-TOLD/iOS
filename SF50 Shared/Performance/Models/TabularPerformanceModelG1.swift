import Foundation

/// Tabular performance model for first-generation SF50 Vision Jet (G1).
///
/// ``TabularPerformanceModelG1`` calculates takeoff and landing performance using
/// direct interpolation from digitized AFM table data. This model performs multi-dimensional
/// linear interpolation to look up values.
///
/// The G1 model uses the original thrust schedule for performance calculations.
///
/// ## Tabular Approach
///
/// Performance values are computed by loading CSV data tables containing digitized
/// AFM chart values, then performing 1D, 2D, or 3D linear interpolation depending
/// on the number of input parameters (weight, altitude, temperature).
///
/// ## Adjustment Factors
///
/// Base performance values are adjusted for environmental conditions using
/// multiplicative factors loaded from additional data tables:
///
/// - Wind (headwind reduces distance, tailwind increases)
/// - Gradient (uphill/downhill)
/// - Surface (unpaved adds margin)
/// - Contamination (snow, slush, water)
///
/// ## Usage
///
/// This model is selected automatically when the user has:
/// - Tabular model enabled in settings (regression disabled)
/// - G1 thrust schedule selected (not updated thrust)
final class TabularPerformanceModelG1: BasePerformanceModel {

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

  private let contaminationCalculator: ContaminationCalculator

  private let enrouteClimb_gradientNormalData: DataTable
  private let enrouteClimb_rateNormalData: DataTable
  private let enrouteClimb_speedNormalData: DataTable
  private let enrouteClimb_gradientIceContaminatedData: DataTable
  private let enrouteClimb_rateIceContaminatedData: DataTable
  private let enrouteClimb_speedIceContaminatedData: DataTable

  // MARK: - Outputs

  override var takeoffRunFt: Value<Double> {
    var run = takeoffRunBaseFt
    run *= takeoffRun_headwindAdjustment
    run *= takeoffRun_tailwindAdjustment
    run *= takeoffRun_uphillAdjustment
    run *= takeoffRun_downhillAdjustment
    return run
  }

  override var takeoffDistanceFt: Value<Double> {
    var distance = takeoffDistanceBaseFt
    distance *= takeoffDistance_headwindAdjustment
    distance *= takeoffDistance_tailwindAdjustment
    if runway.isTurf { distance *= takeoffDistance_unpavedAdjustment }
    return distance
  }

  override var takeoffClimbGradientFtNM: Value<Double> {
    takeoffClimbGradientData.value(for: [weight, altitude, temperature])
  }

  override var takeoffClimbRateFtMin: Value<Double> {
    takeoffClimbRateData.value(for: [weight, altitude, temperature])
  }

  var enrouteClimbGradientFtNM: Value<Double> {
    let iceContaminated = configuration.iceProtection
    let data =
      iceContaminated ? enrouteClimb_gradientIceContaminatedData : enrouteClimb_gradientNormalData
    return data.value(for: [altitude, temperature, weight])
  }

  var enrouteClimbRateFtMin: Value<Double> {
    let iceContaminated = configuration.iceProtection
    let data = iceContaminated ? enrouteClimb_rateIceContaminatedData : enrouteClimb_rateNormalData
    return data.value(for: [altitude, temperature, weight])
  }

  var enrouteClimbSpeedKIAS: Value<Double> {
    let iceContaminated = configuration.iceProtection
    let data =
      iceContaminated ? enrouteClimb_speedIceContaminatedData : enrouteClimb_speedNormalData
    return data.value(for: [altitude, temperature, weight])
  }

  override var VrefKts: Value<Double> {
    vrefData.value(for: [weight])
  }

  override var landingRunFt: Value<Double> {
    var run = landingRun_contaminationAddition(distance: landingRunBaseFt)
    run *= landingRun_headwindAdjustment
    run *= landingRun_tailwindAdjustment
    run *= landingRun_uphillAdjustment
    run *= landingRun_downhillAdjustment
    return run
  }

  override var landingDistanceFt: Value<Double> {
    var distance = contaminationCalculator.landingDistanceContaminationAddition(
      landingDistance: landingDistanceBaseFt,
      landingRun: landingRunBaseFt,
      contamination: notam?.contamination,
      isGroovedOrPFC: runway.isGroovedOrPFC
    )
    distance *= landingDistance_headwindAdjustment
    distance *= landingDistance_tailwindAdjustment
    if runway.isTurf { distance *= landingDistance_unpavedAdjustment }
    return distance
  }

  override var meetsGoAroundClimbGradient: Value<Bool> {
    switch landingDistanceFt {
      case .notAvailable: .notAvailable
      case .notAuthorized: .notAuthorized
      case .offscaleHigh: .value(false)
      default: .value(true)
    }
  }

  // MARK: - Base Values

  private var takeoffRunBaseFt: Value<Double> {
    takeoffRunData.value(
      for: [weight, altitude, temperature],
      clamping: [.clampLow, .clampLow, .clampLow]
    )
  }

  private var takeoffDistanceBaseFt: Value<Double> {
    takeoffDistanceData.value(
      for: [weight, altitude, temperature],
      clamping: [.clampLow, .clampLow, .clampLow]
    )
  }

  private var landingRunBaseFt: Value<Double> {
    landingRunData.value(
      for: [weight, altitude, temperature],
      clamping: [.clampLow, .clampLow, .clampLow]
    )
  }

  private var landingDistanceBaseFt: Value<Double> {
    landingDistanceData.value(
      for: [weight, altitude, temperature],
      clamping: [.clampLow, .clampLow, .clampLow]
    )
  }

  // MARK: - Adjustments

  private var landingDistance_flapsUpAdjustment: Double { 1 + 0.38 }
  private var landingDistance_flapsUpIceAdjustment: Double { 1 + 0.52 }

  private var takeoffRun_headwindAdjustment: Value<Double> {
    PerformanceAdjustments.takeoffRunHeadwindAdjustment(
      data: takeoffRun_headwindData,
      weight: weight,
      headwind: headwind
    )
  }

  private var takeoffDistance_headwindAdjustment: Value<Double> {
    PerformanceAdjustments.takeoffDistanceHeadwindAdjustment(
      data: takeoffDistance_headwindData,
      weight: weight,
      headwind: headwind
    )
  }

  private var takeoffRun_tailwindAdjustment: Value<Double> {
    PerformanceAdjustments.takeoffRunTailwindAdjustment(
      data: takeoffRun_tailwindData,
      weight: weight,
      tailwind: tailwind
    )
  }

  private var takeoffDistance_tailwindAdjustment: Value<Double> {
    PerformanceAdjustments.takeoffDistanceTailwindAdjustment(
      data: takeoffDistance_tailwindData,
      weight: weight,
      tailwind: tailwind
    )
  }

  private var takeoffRun_uphillAdjustment: Value<Double> {
    PerformanceAdjustments.takeoffRunUphillAdjustment(
      data: takeoffRun_uphillData,
      weight: weight,
      uphill: uphill
    )
  }

  private var takeoffRun_downhillAdjustment: Value<Double> {
    PerformanceAdjustments.takeoffRunDownhillAdjustment(
      data: takeoffRun_downhillData,
      weight: weight,
      downhill: downhill
    )
  }

  private var takeoffDistance_unpavedAdjustment: Value<Double> {
    PerformanceAdjustments.takeoffDistanceUnpavedAdjustment(
      data: takeoffDistance_unpavedData,
      weight: weight
    )
  }

  private var landingRun_headwindAdjustment: Value<Double> {
    PerformanceAdjustments.landingRunHeadwindAdjustment(
      data: landingRun_headwindData,
      weight: weight,
      headwind: headwind
    )
  }

  private var landingDistance_headwindAdjustment: Value<Double> {
    PerformanceAdjustments.landingDistanceHeadwindAdjustment(
      data: landingDistance_headwindData,
      weight: weight,
      headwind: headwind
    )
  }

  private var landingRun_tailwindAdjustment: Value<Double> {
    PerformanceAdjustments.landingRunTailwindAdjustment(
      data: landingRun_tailwindData,
      weight: weight,
      tailwind: tailwind
    )
  }

  private var landingDistance_tailwindAdjustment: Value<Double> {
    PerformanceAdjustments.landingDistanceTailwindAdjustment(
      data: landingDistance_tailwindData,
      weight: weight,
      tailwind: tailwind
    )
  }

  private var landingRun_uphillAdjustment: Value<Double> {
    PerformanceAdjustments.landingRunUphillAdjustment(
      data: landingRun_uphillData,
      weight: weight,
      uphill: uphill
    )
  }

  private var landingRun_downhillAdjustment: Value<Double> {
    PerformanceAdjustments.landingRunDownhillAdjustment(
      data: landingRun_downhillData,
      weight: weight,
      downhill: downhill
    )
  }

  private var landingDistance_unpavedAdjustment: Value<Double> {
    PerformanceAdjustments.landingDistanceUnpavedAdjustment(
      data: landingDistance_unpavedData,
      weight: weight
    )
  }

  // MARK: - Initializers

  init(
    conditions: Conditions,
    configuration: Configuration,
    runway: RunwayInput,
    notam: NOTAMInput?,
    aircraftType: AircraftType
  ) {
    let loader = DataTableLoader(aircraftType: aircraftType)
    let vrefPrefix = BasePerformanceModel(
      conditions: conditions,
      configuration: configuration,
      runway: runway,
      notam: notam
    ).vrefPrefix(for: configuration.flapSetting)
    let landingPrefix = BasePerformanceModel(
      conditions: conditions,
      configuration: configuration,
      runway: runway,
      notam: notam
    ).landingPrefix(for: configuration.flapSetting)

    takeoffRunData = loader.loadTakeoffRunData()
    takeoffDistanceData = loader.loadTakeoffDistanceData()
    takeoffClimbGradientData = loader.loadTakeoffClimbGradientData()
    takeoffClimbRateData = loader.loadTakeoffClimbRateData()
    vrefData = loader.loadVrefData(vrefPrefix: vrefPrefix)
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

    contaminationCalculator = ContaminationCalculator(
      aircraftType: aircraftType,
      loader: loader
    )

    enrouteClimb_gradientNormalData = loader.loadEnrouteClimbGradientData(
      iceContaminated: false
    )
    enrouteClimb_rateNormalData = loader.loadEnrouteClimbRateData(iceContaminated: false)
    enrouteClimb_speedNormalData = loader.loadEnrouteClimbSpeedData(iceContaminated: false)
    enrouteClimb_gradientIceContaminatedData = loader.loadEnrouteClimbGradientData(
      iceContaminated: true
    )
    enrouteClimb_rateIceContaminatedData = loader.loadEnrouteClimbRateData(
      iceContaminated: true
    )
    enrouteClimb_speedIceContaminatedData = loader.loadEnrouteClimbSpeedData(
      iceContaminated: true
    )

    super.init(conditions: conditions, configuration: configuration, runway: runway, notam: notam)
  }

  // MARK: - Functions

  private func landingRun_contaminationAddition(distance: Value<Double>) -> Value<Double> {
    contaminationCalculator.landingRunContaminationAddition(
      distance: distance,
      contamination: notam?.contamination,
      isGroovedOrPFC: runway.isGroovedOrPFC
    )
  }
}
