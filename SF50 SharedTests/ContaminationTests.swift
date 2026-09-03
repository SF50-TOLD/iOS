import Foundation
import Testing

@testable import SF50_Shared

/// Comprehensive tests for runway contamination effects on landing performance.
///
/// This test suite verifies that contamination correctly increases landing distances
/// according to the performance data in the AFM. Tests cover all contamination types
/// (water, slush, dry snow, compact snow) across both tabular and regression models.
struct ContaminationTests {

  // MARK: - Contamination Increases Landing Run

  @Test("Water contamination increases landing run - Tabular G1")
  func waterContamination_increasesLandingRun_tabularG1() {
    let conditions = Helper.createTestConditions(temperature: 20)
    let config = Helper.createTestConfiguration(weight: 5000)
    let runway = Helper.createTestRunway()
    let runwayInput = RunwayInput(from: runway, airport: runway.airport)

    // Model without contamination
    let cleanModel = TabularPerformanceModel(
      conditions: conditions,
      configuration: config,
      runway: runwayInput,
      notam: nil,
      aircraftType: .g1
    )

    let cleanRun: Double
    switch cleanModel.landingRunFt {
      case .value(let val):
        cleanRun = val
      case .valueWithUncertainty(let val, _):
        cleanRun = val
      default:
        PerformanceCase(for: cleanModel, aircraftType: .g1)
          .fail("Expected clean landing run value", computing: "clean landing run")
        return
    }

    // Model with water contamination (0.25 inches)
    let waterContamination = Contamination.waterOrSlush(depth: .init(value: 0.25, unit: .inches))
    let contaminatedNotam = NOTAMInput(
      contaminationType: waterContamination.type,
      contaminationDepth: .init(value: waterContamination.depth ?? 0, unit: .meters),
      takeoffDistanceShortening: .init(value: 0, unit: .feet),
      landingDistanceShortening: .init(value: 0, unit: .feet),
      obstacleHeight: .init(value: 0, unit: .feet),
      obstacleDistance: .init(value: 0, unit: .nauticalMiles)
    )

    let contaminatedModel = TabularPerformanceModel(
      conditions: conditions,
      configuration: config,
      runway: runwayInput,
      notam: contaminatedNotam,
      aircraftType: .g1
    )

    guard case .value(let contaminatedRun) = contaminatedModel.landingRunFt else {
      PerformanceCase(for: contaminatedModel, aircraftType: .g1)
        .fail("Expected contaminated landing run value", computing: "contaminated landing run")
      return
    }

    PerformanceCase(for: cleanModel, aircraftType: .g1)
      .expect(cleanRun, of: 1961.19, computing: "clean landing run")
    PerformanceCase(for: contaminatedModel, aircraftType: .g1)
      .expect(contaminatedRun, of: 2946.79, computing: "contaminated landing run")
  }

  @Test("Slush contamination increases landing run - Tabular G2+")
  func slushContamination_increasesLandingRun_tabularG2Plus() {
    let conditions = Helper.createTestConditions(temperature: 20)
    let config = Helper.createTestConfiguration(weight: 5000)
    let runway = Helper.createTestRunway()
    let runwayInput = RunwayInput(from: runway, airport: runway.airport)

    let cleanModel = TabularPerformanceModel(
      conditions: conditions,
      configuration: config,
      runway: runwayInput,
      notam: nil,
      aircraftType: .g2Plus
    )

    let cleanRun: Double
    switch cleanModel.landingRunFt {
      case .value(let val):
        cleanRun = val
      case .valueWithUncertainty(let val, _):
        cleanRun = val
      default:
        PerformanceCase(for: cleanModel, aircraftType: .g2Plus)
          .fail("Expected clean landing run value", computing: "clean landing run")
        return
    }

    // Model with slush contamination (0.5 inches)
    let slushContamination = Contamination.slushOrWetSnow(depth: .init(value: 0.5, unit: .inches))
    let contaminatedNotam = NOTAMInput(
      contaminationType: slushContamination.type,
      contaminationDepth: .init(value: slushContamination.depth ?? 0, unit: .meters),
      takeoffDistanceShortening: .init(value: 0, unit: .feet),
      landingDistanceShortening: .init(value: 0, unit: .feet),
      obstacleHeight: .init(value: 0, unit: .feet),
      obstacleDistance: .init(value: 0, unit: .nauticalMiles)
    )

    let contaminatedModel = TabularPerformanceModel(
      conditions: conditions,
      configuration: config,
      runway: runwayInput,
      notam: contaminatedNotam,
      aircraftType: .g2Plus
    )

    guard case .value(let contaminatedRun) = contaminatedModel.landingRunFt else {
      PerformanceCase(for: contaminatedModel, aircraftType: .g2Plus)
        .fail("Expected contaminated landing run value", computing: "contaminated landing run")
      return
    }

    PerformanceCase(for: cleanModel, aircraftType: .g2Plus)
      .expect(cleanRun, of: 1961.19, computing: "clean landing run")
    PerformanceCase(for: contaminatedModel, aircraftType: .g2Plus)
      .expect(contaminatedRun, of: 2725.67, computing: "contaminated landing run")
  }

  @Test("Dry snow contamination increases landing run - Regression G1")
  func drySnowContamination_increasesLandingRun_regressionG1() {
    let conditions = Helper.createTestConditions(temperature: -5)  // Cold for snow
    let config = Helper.createTestConfiguration(weight: 5500)
    let runway = Helper.createTestRunway()
    let runwayInput = RunwayInput(from: runway, airport: runway.airport)

    let cleanModel = RegressionPerformanceModel(
      conditions: conditions,
      configuration: config,
      runway: runwayInput,
      notam: nil,
      aircraftType: .g1
    )

    guard case .valueWithUncertainty(let cleanRun, _) = cleanModel.landingRunFt else {
      PerformanceCase(for: cleanModel, aircraftType: .g1)
        .fail("Expected clean landing run value", computing: "clean landing run")
      return
    }

    let drySnowContamination = Contamination.drySnow
    let contaminatedNotam = NOTAMInput(
      contaminationType: drySnowContamination.type,
      contaminationDepth: .init(value: drySnowContamination.depth ?? 0, unit: .meters),
      takeoffDistanceShortening: .init(value: 0, unit: .feet),
      landingDistanceShortening: .init(value: 0, unit: .feet),
      obstacleHeight: .init(value: 0, unit: .feet),
      obstacleDistance: .init(value: 0, unit: .nauticalMiles)
    )

    let contaminatedModel = RegressionPerformanceModel(
      conditions: conditions,
      configuration: config,
      runway: runwayInput,
      notam: contaminatedNotam,
      aircraftType: .g1
    )

    guard case .valueWithUncertainty(let contaminatedRun, _) = contaminatedModel.landingRunFt
    else {
      PerformanceCase(for: contaminatedModel, aircraftType: .g1)
        .fail("Expected contaminated landing run value", computing: "contaminated landing run")
      return
    }

    PerformanceCase(for: cleanModel, aircraftType: .g1)
      .expect(cleanRun, of: 1983.17, computing: "clean landing run")
    PerformanceCase(for: contaminatedModel, aircraftType: .g1)
      .expect(contaminatedRun, of: 2640.79, computing: "contaminated landing run")
  }

  @Test("Compact snow contamination increases landing run - Regression G2+")
  func compactSnowContamination_increasesLandingRun_regressionG2Plus() {
    let conditions = Helper.createTestConditions(temperature: -10)
    let config = Helper.createTestConfiguration(weight: 5000)
    let runway = Helper.createTestRunway()
    let runwayInput = RunwayInput(from: runway, airport: runway.airport)

    let cleanModel = RegressionPerformanceModel(
      conditions: conditions,
      configuration: config,
      runway: runwayInput,
      notam: nil,
      aircraftType: .g2Plus
    )

    let cleanCase = PerformanceCase(for: cleanModel, aircraftType: .g2Plus)
    guard case .valueWithUncertainty(let cleanRun, _) = cleanModel.landingRunFt else {
      cleanCase.fail("Expected clean landing run value", computing: "clean landing run")
      return
    }

    let compactSnowContamination = Contamination.compactSnow
    let contaminatedNotam = NOTAMInput(
      contaminationType: compactSnowContamination.type,
      contaminationDepth: .init(value: compactSnowContamination.depth ?? 0, unit: .meters),
      takeoffDistanceShortening: .init(value: 0, unit: .feet),
      landingDistanceShortening: .init(value: 0, unit: .feet),
      obstacleHeight: .init(value: 0, unit: .feet),
      obstacleDistance: .init(value: 0, unit: .nauticalMiles)
    )

    let contaminatedModel = RegressionPerformanceModel(
      conditions: conditions,
      configuration: config,
      runway: runwayInput,
      notam: contaminatedNotam,
      aircraftType: .g2Plus
    )

    let contaminatedCase = PerformanceCase(for: contaminatedModel, aircraftType: .g2Plus)
    guard case .valueWithUncertainty(let contaminatedRun, _) = contaminatedModel.landingRunFt
    else {
      contaminatedCase
        .fail("Expected contaminated landing run value", computing: "contaminated landing run")
      return
    }

    PerformanceCase.expect(
      contaminatedRun > cleanRun * 1.5,
      "Compact snow should increase landing run by more than half",
      results: [
        "clean landing run": cleanCase.computed(cleanRun),
        "contaminated landing run": contaminatedCase.computed(contaminatedRun)
      ]
    )
  }

  // MARK: - Contamination Increases Total Landing Distance

  @Test("Water contamination increases total landing distance - Tabular G1")
  func waterContamination_increasesTotalLandingDistance_tabularG1() {
    let conditions = Helper.createTestConditions(temperature: 20)
    let config = Helper.createTestConfiguration(weight: 5000)
    let runway = Helper.createTestRunway()
    let runwayInput = RunwayInput(from: runway, airport: runway.airport)

    let cleanModel = TabularPerformanceModel(
      conditions: conditions,
      configuration: config,
      runway: runwayInput,
      notam: nil,
      aircraftType: .g1
    )

    let cleanDistance: Double
    switch cleanModel.landingDistanceFt {
      case .value(let val):
        cleanDistance = val
      case .valueWithUncertainty(let val, _):
        cleanDistance = val
      default:
        PerformanceCase(for: cleanModel, aircraftType: .g1)
          .fail("Expected clean landing distance value", computing: "clean landing distance")
        return
    }

    let waterContamination3 = Contamination.waterOrSlush(depth: .init(value: 0.5, unit: .inches))
    let contaminatedNotam = NOTAMInput(
      contaminationType: waterContamination3.type,
      contaminationDepth: .init(value: waterContamination3.depth ?? 0, unit: .meters),
      takeoffDistanceShortening: .init(value: 0, unit: .feet),
      landingDistanceShortening: .init(value: 0, unit: .feet),
      obstacleHeight: .init(value: 0, unit: .feet),
      obstacleDistance: .init(value: 0, unit: .nauticalMiles)
    )

    let contaminatedModel = TabularPerformanceModel(
      conditions: conditions,
      configuration: config,
      runway: runwayInput,
      notam: contaminatedNotam,
      aircraftType: .g1
    )

    guard case .value(let contaminatedDistance) = contaminatedModel.landingDistanceFt else {
      PerformanceCase(for: contaminatedModel, aircraftType: .g1)
        .fail(
          "Expected contaminated landing distance value",
          computing: "contaminated landing distance"
        )
      return
    }

    PerformanceCase(for: cleanModel, aircraftType: .g1)
      .expect(cleanDistance, of: 2789.19, computing: "clean landing distance")
    PerformanceCase(for: contaminatedModel, aircraftType: .g1)
      .expect(contaminatedDistance, of: 3347.55, computing: "contaminated landing distance")
  }

  @Test("Slush contamination increases total landing distance - Tabular G2+")
  func slushContamination_increasesTotalLandingDistance_tabularG2Plus() {
    let conditions = Helper.createTestConditions(temperature: 5)
    let config = Helper.createTestConfiguration(weight: 5500, flapSetting: .flaps100)
    let runway = Helper.createTestRunway()
    let runwayInput = RunwayInput(from: runway, airport: runway.airport)

    let cleanModel = TabularPerformanceModel(
      conditions: conditions,
      configuration: config,
      runway: runwayInput,
      notam: nil,
      aircraftType: .g2Plus
    )

    let cleanDistance: Double
    switch cleanModel.landingDistanceFt {
      case .value(let val):
        cleanDistance = val
      case .valueWithUncertainty(let val, _):
        cleanDistance = val
      default:
        PerformanceCase(for: cleanModel, aircraftType: .g2Plus)
          .fail("Expected clean landing distance value", computing: "clean landing distance")
        return
    }

    let slushContamination2 = Contamination.slushOrWetSnow(depth: .init(value: 0.75, unit: .inches))
    let contaminatedNotam = NOTAMInput(
      contaminationType: slushContamination2.type,
      contaminationDepth: .init(value: slushContamination2.depth ?? 0, unit: .meters),
      takeoffDistanceShortening: .init(value: 0, unit: .feet),
      landingDistanceShortening: .init(value: 0, unit: .feet),
      obstacleHeight: .init(value: 0, unit: .feet),
      obstacleDistance: .init(value: 0, unit: .nauticalMiles)
    )

    let contaminatedModel = TabularPerformanceModel(
      conditions: conditions,
      configuration: config,
      runway: runwayInput,
      notam: contaminatedNotam,
      aircraftType: .g2Plus
    )

    guard case .value(let contaminatedDistance) = contaminatedModel.landingDistanceFt else {
      PerformanceCase(for: contaminatedModel, aircraftType: .g2Plus)
        .fail(
          "Expected contaminated landing distance value",
          computing: "contaminated landing distance"
        )
      return
    }

    PerformanceCase(for: cleanModel, aircraftType: .g2Plus)
      .expect(cleanDistance, of: 2431.57, computing: "clean landing distance")
    PerformanceCase(for: contaminatedModel, aircraftType: .g2Plus)
      .expect(contaminatedDistance, of: 3034.39, computing: "contaminated landing distance")
  }

  @Test("Dry snow contamination increases total landing distance - Regression G1")
  func drySnowContamination_increasesTotalLandingDistance_regressionG1() {
    let conditions = Helper.createTestConditions(temperature: -5)
    let config = Helper.createTestConfiguration(weight: 5000)
    let runway = Helper.createTestRunway()
    let runwayInput = RunwayInput(from: runway, airport: runway.airport)

    let cleanModel = RegressionPerformanceModel(
      conditions: conditions,
      configuration: config,
      runway: runwayInput,
      notam: nil,
      aircraftType: .g1
    )

    let cleanCase = PerformanceCase(for: cleanModel, aircraftType: .g1)
    guard case .valueWithUncertainty(let cleanDistance, _) = cleanModel.landingDistanceFt else {
      cleanCase.fail("Expected clean landing distance value", computing: "clean landing distance")
      return
    }

    let drySnowContamination2 = Contamination.drySnow
    let contaminatedNotam = NOTAMInput(
      contaminationType: drySnowContamination2.type,
      contaminationDepth: .init(value: drySnowContamination2.depth ?? 0, unit: .meters),
      takeoffDistanceShortening: .init(value: 0, unit: .feet),
      landingDistanceShortening: .init(value: 0, unit: .feet),
      obstacleHeight: .init(value: 0, unit: .feet),
      obstacleDistance: .init(value: 0, unit: .nauticalMiles)
    )

    let contaminatedModel = RegressionPerformanceModel(
      conditions: conditions,
      configuration: config,
      runway: runwayInput,
      notam: contaminatedNotam,
      aircraftType: .g1
    )

    let contaminatedCase = PerformanceCase(for: contaminatedModel, aircraftType: .g1)
    guard
      case .valueWithUncertainty(let contaminatedDistance, _) = contaminatedModel
        .landingDistanceFt
    else {
      contaminatedCase
        .fail(
          "Expected contaminated landing distance value",
          computing: "contaminated landing distance"
        )
      return
    }

    PerformanceCase.expect(
      contaminatedDistance > cleanDistance * 1.15,
      "Dry snow should increase landing distance by more than 15%",
      results: [
        "clean landing distance": cleanCase.computed(cleanDistance),
        "contaminated landing distance": contaminatedCase.computed(contaminatedDistance)
      ]
    )
  }

  @Test("Compact snow contamination increases total landing distance - Regression G2+")
  func compactSnowContamination_increasesTotalLandingDistance_regressionG2Plus() {
    let conditions = Helper.createTestConditions(temperature: -10)
    let config = Helper.createTestConfiguration(weight: 5500)
    let runway = Helper.createTestRunway()
    let runwayInput = RunwayInput(from: runway, airport: runway.airport)

    let cleanModel = RegressionPerformanceModel(
      conditions: conditions,
      configuration: config,
      runway: runwayInput,
      notam: nil,
      aircraftType: .g2Plus
    )

    guard case .valueWithUncertainty(let cleanDistance, _) = cleanModel.landingDistanceFt else {
      PerformanceCase(for: cleanModel, aircraftType: .g2Plus)
        .fail("Expected clean landing distance value", computing: "clean landing distance")
      return
    }

    let compactSnowContamination2 = Contamination.compactSnow
    let contaminatedNotam = NOTAMInput(
      contaminationType: compactSnowContamination2.type,
      contaminationDepth: .init(value: compactSnowContamination2.depth ?? 0, unit: .meters),
      takeoffDistanceShortening: .init(value: 0, unit: .feet),
      landingDistanceShortening: .init(value: 0, unit: .feet),
      obstacleHeight: .init(value: 0, unit: .feet),
      obstacleDistance: .init(value: 0, unit: .nauticalMiles)
    )

    let contaminatedModel = RegressionPerformanceModel(
      conditions: conditions,
      configuration: config,
      runway: runwayInput,
      notam: contaminatedNotam,
      aircraftType: .g2Plus
    )

    guard
      case .valueWithUncertainty(let contaminatedDistance, _) = contaminatedModel
        .landingDistanceFt
    else {
      PerformanceCase(for: contaminatedModel, aircraftType: .g2Plus)
        .fail(
          "Expected contaminated landing distance value",
          computing: "contaminated landing distance"
        )
      return
    }

    PerformanceCase(for: cleanModel, aircraftType: .g2Plus)
      .expect(cleanDistance, of: 2933.23, computing: "clean landing distance")
    PerformanceCase(for: contaminatedModel, aircraftType: .g2Plus)
      .expect(contaminatedDistance, of: 4064.51, computing: "contaminated landing distance")
  }

  // MARK: - Contamination Depth Effects

  @Test("Shallower water depth causes greater distance increase per AFM")
  func shallowerWaterDepth_causesGreaterDistanceIncrease() {
    let conditions = Helper.createTestConditions(temperature: 20)
    let config = Helper.createTestConfiguration(weight: 5000)
    let runway = Helper.createTestRunway()
    let runwayInput = RunwayInput(from: runway, airport: runway.airport)

    // Shallow water (0.25 inches)
    let shallowWaterContamination = Contamination.waterOrSlush(
      depth: .init(value: 0.25, unit: .inches)
    )
    let shallowNotam = NOTAMInput(
      contaminationType: shallowWaterContamination.type,
      contaminationDepth: .init(value: shallowWaterContamination.depth ?? 0, unit: .meters),
      takeoffDistanceShortening: .init(value: 0, unit: .feet),
      landingDistanceShortening: .init(value: 0, unit: .feet),
      obstacleHeight: .init(value: 0, unit: .feet),
      obstacleDistance: .init(value: 0, unit: .nauticalMiles)
    )

    let shallowModel = TabularPerformanceModel(
      conditions: conditions,
      configuration: config,
      runway: runwayInput,
      notam: shallowNotam,
      aircraftType: .g1
    )

    // Deep water (0.75 inches)
    let deepWaterContamination = Contamination.waterOrSlush(
      depth: .init(value: 0.75, unit: .inches)
    )
    let deepNotam = NOTAMInput(
      contaminationType: deepWaterContamination.type,
      contaminationDepth: .init(value: deepWaterContamination.depth ?? 0, unit: .meters),
      takeoffDistanceShortening: .init(value: 0, unit: .feet),
      landingDistanceShortening: .init(value: 0, unit: .feet),
      obstacleHeight: .init(value: 0, unit: .feet),
      obstacleDistance: .init(value: 0, unit: .nauticalMiles)
    )

    let deepModel = TabularPerformanceModel(
      conditions: conditions,
      configuration: config,
      runway: runwayInput,
      notam: deepNotam,
      aircraftType: .g1
    )

    let shallowRun: Double
    let deepRun: Double

    switch shallowModel.landingRunFt {
      case .value(let val), .valueWithUncertainty(let val, _):
        shallowRun = val
      default:
        PerformanceCase(for: shallowModel, aircraftType: .g1)
          .fail("Expected landing run values", computing: "shallow landing run")
        return
    }

    switch deepModel.landingRunFt {
      case .value(let val), .valueWithUncertainty(let val, _):
        deepRun = val
      default:
        PerformanceCase(for: deepModel, aircraftType: .g1)
          .fail("Expected landing run values", computing: "deep landing run")
        return
    }

    PerformanceCase(for: shallowModel, aircraftType: .g1)
      .expect(shallowRun, of: 2946.79, computing: "landing run")
    PerformanceCase(for: deepModel, aircraftType: .g1)
      .expect(deepRun, of: 2519.55, computing: "landing run")
  }

  // MARK: - Contamination with Other Factors

  @Test("Contamination combined with headwind")
  func contamination_combinedWithHeadwind() {
    let headwindConditions = Helper.createTestConditions(
      temperature: 20,
      windDirection: 360,
      windSpeed: 10
    )
    let config = Helper.createTestConfiguration(weight: 5000)
    let runway = Helper.createTestRunway(heading: 360)
    let runwayInput = RunwayInput(from: runway, airport: runway.airport)

    let cleanModel = TabularPerformanceModel(
      conditions: headwindConditions,
      configuration: config,
      runway: runwayInput,
      notam: nil,
      aircraftType: .g1
    )

    let waterContamination4 = Contamination.waterOrSlush(depth: .init(value: 0.5, unit: .inches))
    let contaminatedNotam = NOTAMInput(
      contaminationType: waterContamination4.type,
      contaminationDepth: .init(value: waterContamination4.depth ?? 0, unit: .meters),
      takeoffDistanceShortening: .init(value: 0, unit: .feet),
      landingDistanceShortening: .init(value: 0, unit: .feet),
      obstacleHeight: .init(value: 0, unit: .feet),
      obstacleDistance: .init(value: 0, unit: .nauticalMiles)
    )

    let contaminatedModel = TabularPerformanceModel(
      conditions: headwindConditions,
      configuration: config,
      runway: runwayInput,
      notam: contaminatedNotam,
      aircraftType: .g1
    )

    let cleanDistance: Double
    let contaminatedDistance: Double

    switch cleanModel.landingDistanceFt {
      case .value(let val), .valueWithUncertainty(let val, _):
        cleanDistance = val
      default:
        PerformanceCase(for: cleanModel, aircraftType: .g1)
          .fail("Expected landing distance values", computing: "clean landing distance")
        return
    }

    switch contaminatedModel.landingDistanceFt {
      case .value(let val), .valueWithUncertainty(let val, _):
        contaminatedDistance = val
      default:
        PerformanceCase(for: contaminatedModel, aircraftType: .g1)
          .fail("Expected landing distance values", computing: "contaminated landing distance")
        return
    }

    PerformanceCase(for: cleanModel, aircraftType: .g1)
      .expect(cleanDistance, of: 2607.23, computing: "clean landing distance")
    PerformanceCase(for: contaminatedModel, aircraftType: .g1)
      .expect(contaminatedDistance, of: 3129.16, computing: "contaminated landing distance")
  }

  @Test("Contamination combined with uphill slope")
  func contamination_combinedWithUphillSlope() {
    let conditions = Helper.createTestConditions(temperature: 20)
    let config = Helper.createTestConfiguration(weight: 5000)
    let runway = Helper.createTestRunway(slope: 1.0)  // 1% uphill
    let runwayInput = RunwayInput(from: runway, airport: runway.airport)

    let cleanModel = TabularPerformanceModel(
      conditions: conditions,
      configuration: config,
      runway: runwayInput,
      notam: nil,
      aircraftType: .g1
    )

    let compactSnowContamination3 = Contamination.compactSnow
    let contaminatedNotam = NOTAMInput(
      contaminationType: compactSnowContamination3.type,
      contaminationDepth: .init(value: compactSnowContamination3.depth ?? 0, unit: .meters),
      takeoffDistanceShortening: .init(value: 0, unit: .feet),
      landingDistanceShortening: .init(value: 0, unit: .feet),
      obstacleHeight: .init(value: 0, unit: .feet),
      obstacleDistance: .init(value: 0, unit: .nauticalMiles)
    )

    let contaminatedModel = TabularPerformanceModel(
      conditions: conditions,
      configuration: config,
      runway: runwayInput,
      notam: contaminatedNotam,
      aircraftType: .g1
    )

    let cleanDistance: Double
    let contaminatedDistance: Double

    switch cleanModel.landingDistanceFt {
      case .value(let val), .valueWithUncertainty(let val, _):
        cleanDistance = val
      default:
        PerformanceCase(for: cleanModel, aircraftType: .g1)
          .fail("Expected landing distance values", computing: "clean landing distance")
        return
    }

    switch contaminatedModel.landingDistanceFt {
      case .value(let val), .valueWithUncertainty(let val, _):
        contaminatedDistance = val
      default:
        PerformanceCase(for: contaminatedModel, aircraftType: .g1)
          .fail("Expected landing distance values", computing: "contaminated landing distance")
        return
    }

    PerformanceCase(for: cleanModel, aircraftType: .g1)
      .expect(cleanDistance, of: 2789.19, computing: "clean landing distance")
    PerformanceCase(for: contaminatedModel, aircraftType: .g1)
      .expect(contaminatedDistance, of: 3927.85, computing: "contaminated landing distance")
  }

  // MARK: - Wet Runway Tests (G2/G2+ AFM Reissue A)

  @Test("Wet runway contamination increases landing run by 15% - Tabular G2+")
  func wetRunwayContamination_increasesLandingRun_tabularG2Plus() {
    let conditions = Helper.createTestConditions(temperature: 20)
    let config = Helper.createTestConfiguration(weight: 5550)
    let runway = Helper.createTestRunway()
    let runwayInput = RunwayInput(from: runway, airport: runway.airport)

    // Model without contamination
    let cleanModel = TabularPerformanceModel(
      conditions: conditions,
      configuration: config,
      runway: runwayInput,
      notam: nil,
      aircraftType: .g2Plus
    )

    let cleanRun: Double
    switch cleanModel.landingRunFt {
      case .value(let val):
        cleanRun = val
      case .valueWithUncertainty(let val, _):
        cleanRun = val
      default:
        PerformanceCase(for: cleanModel, aircraftType: .g2Plus)
          .fail("Expected clean landing run value", computing: "clean landing run")
        return
    }

    // Model with wet runway contamination
    let wetRunwayContamination = Contamination.wetRunway
    let contaminatedNotam = NOTAMInput(
      contaminationType: wetRunwayContamination.type,
      contaminationDepth: .init(value: 0, unit: .meters),
      takeoffDistanceShortening: .init(value: 0, unit: .feet),
      landingDistanceShortening: .init(value: 0, unit: .feet),
      obstacleHeight: .init(value: 0, unit: .feet),
      obstacleDistance: .init(value: 0, unit: .nauticalMiles)
    )

    let contaminatedModel = TabularPerformanceModel(
      conditions: conditions,
      configuration: config,
      runway: runwayInput,
      notam: contaminatedNotam,
      aircraftType: .g2Plus
    )

    let contaminatedRun: Double
    switch contaminatedModel.landingRunFt {
      case .value(let val):
        contaminatedRun = val
      case .valueWithUncertainty(let val, _):
        contaminatedRun = val
      default:
        PerformanceCase(for: contaminatedModel, aircraftType: .g2Plus)
          .fail("Expected contaminated landing run value", computing: "contaminated landing run")
        return
    }

    PerformanceCase(for: contaminatedModel, aircraftType: .g2Plus)
      .expect(contaminatedRun, of: cleanRun * 1.15, computing: "wet landing run")
  }

  @Test("Wet runway contamination increases landing run by 15% - Regression G2+")
  func wetRunwayContamination_increasesLandingRun_regressionG2Plus() {
    let conditions = Helper.createTestConditions(temperature: 20)
    let config = Helper.createTestConfiguration(weight: 5550)
    let runway = Helper.createTestRunway()
    let runwayInput = RunwayInput(from: runway, airport: runway.airport)

    // Model without contamination
    let cleanModel = RegressionPerformanceModel(
      conditions: conditions,
      configuration: config,
      runway: runwayInput,
      notam: nil,
      aircraftType: .g2Plus
    )

    guard case .valueWithUncertainty(let cleanRun, _) = cleanModel.landingRunFt else {
      PerformanceCase(for: cleanModel, aircraftType: .g2Plus)
        .fail("Expected clean landing run value", computing: "clean landing run")
      return
    }

    // Model with wet runway contamination
    let wetRunwayContamination = Contamination.wetRunway
    let contaminatedNotam = NOTAMInput(
      contaminationType: wetRunwayContamination.type,
      contaminationDepth: .init(value: 0, unit: .meters),
      takeoffDistanceShortening: .init(value: 0, unit: .feet),
      landingDistanceShortening: .init(value: 0, unit: .feet),
      obstacleHeight: .init(value: 0, unit: .feet),
      obstacleDistance: .init(value: 0, unit: .nauticalMiles)
    )

    let contaminatedModel = RegressionPerformanceModel(
      conditions: conditions,
      configuration: config,
      runway: runwayInput,
      notam: contaminatedNotam,
      aircraftType: .g2Plus
    )

    guard case .valueWithUncertainty(let contaminatedRun, _) = contaminatedModel.landingRunFt else {
      PerformanceCase(for: contaminatedModel, aircraftType: .g2Plus)
        .fail("Expected contaminated landing run value", computing: "contaminated landing run")
      return
    }

    PerformanceCase(for: contaminatedModel, aircraftType: .g2Plus)
      .expect(contaminatedRun, of: cleanRun * 1.15, computing: "wet landing run")
  }

  @Test("Wet runway contamination has no effect on G1 - Tabular")
  func wetRunwayContamination_noEffectOnG1_tabular() {
    let conditions = Helper.createTestConditions(temperature: 20)
    let config = Helper.createTestConfiguration(weight: 5550)
    let runway = Helper.createTestRunway()
    let runwayInput = RunwayInput(from: runway, airport: runway.airport)

    // Model without contamination
    let cleanModel = TabularPerformanceModel(
      conditions: conditions,
      configuration: config,
      runway: runwayInput,
      notam: nil,
      aircraftType: .g1
    )

    let cleanRun: Double
    switch cleanModel.landingRunFt {
      case .value(let val):
        cleanRun = val
      case .valueWithUncertainty(let val, _):
        cleanRun = val
      default:
        PerformanceCase(for: cleanModel, aircraftType: .g1)
          .fail("Expected clean landing run value", computing: "clean landing run")
        return
    }

    // Model with wet runway contamination
    let wetRunwayContamination = Contamination.wetRunway
    let contaminatedNotam = NOTAMInput(
      contaminationType: wetRunwayContamination.type,
      contaminationDepth: .init(value: 0, unit: .meters),
      takeoffDistanceShortening: .init(value: 0, unit: .feet),
      landingDistanceShortening: .init(value: 0, unit: .feet),
      obstacleHeight: .init(value: 0, unit: .feet),
      obstacleDistance: .init(value: 0, unit: .nauticalMiles)
    )

    let contaminatedModel = TabularPerformanceModel(
      conditions: conditions,
      configuration: config,
      runway: runwayInput,
      notam: contaminatedNotam,
      aircraftType: .g1
    )

    let contaminatedRun: Double
    switch contaminatedModel.landingRunFt {
      case .value(let val):
        contaminatedRun = val
      case .valueWithUncertainty(let val, _):
        contaminatedRun = val
      default:
        PerformanceCase(for: contaminatedModel, aircraftType: .g1)
          .fail("Expected contaminated landing run value", computing: "contaminated landing run")
        return
    }

    PerformanceCase(for: contaminatedModel, aircraftType: .g1)
      .expect(contaminatedRun, isWithin: 0.001, of: cleanRun, computing: "wet landing run")
  }

  @Test("Wet runway contamination increases landing run by 15% - Regression G1")
  func wetRunwayContamination_increasesLandingRun_regressionG1() {
    let conditions = Helper.createTestConditions(temperature: 20)
    let config = Helper.createTestConfiguration(weight: 5550)
    let runway = Helper.createTestRunway()
    let runwayInput = RunwayInput(from: runway, airport: runway.airport)

    // Model without contamination
    let cleanModel = RegressionPerformanceModel(
      conditions: conditions,
      configuration: config,
      runway: runwayInput,
      notam: nil,
      aircraftType: .g1
    )

    guard case .valueWithUncertainty(let cleanRun, _) = cleanModel.landingRunFt else {
      PerformanceCase(for: cleanModel, aircraftType: .g1)
        .fail("Expected clean landing run value", computing: "clean landing run")
      return
    }

    // Model with wet runway contamination
    let wetRunwayContamination = Contamination.wetRunway
    let contaminatedNotam = NOTAMInput(
      contaminationType: wetRunwayContamination.type,
      contaminationDepth: .init(value: 0, unit: .meters),
      takeoffDistanceShortening: .init(value: 0, unit: .feet),
      landingDistanceShortening: .init(value: 0, unit: .feet),
      obstacleHeight: .init(value: 0, unit: .feet),
      obstacleDistance: .init(value: 0, unit: .nauticalMiles)
    )

    let contaminatedModel = RegressionPerformanceModel(
      conditions: conditions,
      configuration: config,
      runway: runwayInput,
      notam: contaminatedNotam,
      aircraftType: .g1
    )

    guard case .valueWithUncertainty(let contaminatedRun, _) = contaminatedModel.landingRunFt else {
      PerformanceCase(for: contaminatedModel, aircraftType: .g1)
        .fail("Expected contaminated landing run value", computing: "contaminated landing run")
      return
    }

    PerformanceCase(for: contaminatedModel, aircraftType: .g1)
      .expect(contaminatedRun, of: cleanRun * 1.15, computing: "wet landing run")
  }

  @Test("Wet runway contamination increases total landing distance - G2+")
  func wetRunwayContamination_increasesTotalLandingDistance_G2Plus() {
    let conditions = Helper.createTestConditions(temperature: 20)
    let config = Helper.createTestConfiguration(weight: 5550)
    let runway = Helper.createTestRunway()
    let runwayInput = RunwayInput(from: runway, airport: runway.airport)

    let cleanModel = TabularPerformanceModel(
      conditions: conditions,
      configuration: config,
      runway: runwayInput,
      notam: nil,
      aircraftType: .g2Plus
    )

    let cleanCase = PerformanceCase(for: cleanModel, aircraftType: .g2Plus)
    let cleanDistance: Double
    switch cleanModel.landingDistanceFt {
      case .value(let val):
        cleanDistance = val
      case .valueWithUncertainty(let val, _):
        cleanDistance = val
      default:
        cleanCase.fail("Expected clean landing distance value", computing: "clean landing distance")
        return
    }

    let wetRunwayContamination = Contamination.wetRunway
    let contaminatedNotam = NOTAMInput(
      contaminationType: wetRunwayContamination.type,
      contaminationDepth: .init(value: 0, unit: .meters),
      takeoffDistanceShortening: .init(value: 0, unit: .feet),
      landingDistanceShortening: .init(value: 0, unit: .feet),
      obstacleHeight: .init(value: 0, unit: .feet),
      obstacleDistance: .init(value: 0, unit: .nauticalMiles)
    )

    let contaminatedModel = TabularPerformanceModel(
      conditions: conditions,
      configuration: config,
      runway: runwayInput,
      notam: contaminatedNotam,
      aircraftType: .g2Plus
    )

    let contaminatedCase = PerformanceCase(for: contaminatedModel, aircraftType: .g2Plus)
    let contaminatedDistance: Double
    switch contaminatedModel.landingDistanceFt {
      case .value(let val):
        contaminatedDistance = val
      case .valueWithUncertainty(let val, _):
        contaminatedDistance = val
      default:
        contaminatedCase
          .fail(
            "Expected contaminated landing distance value",
            computing: "contaminated landing distance"
          )
        return
    }

    PerformanceCase.expect(
      contaminatedDistance > cleanDistance,
      "A wet runway's longer landing run should lengthen the total landing distance",
      results: [
        "clean landing distance": cleanCase.computed(cleanDistance),
        "contaminated landing distance": contaminatedCase.computed(contaminatedDistance)
      ]
    )
  }

  // MARK: - Logical Consistency Tests

  @Test("Landing run never exceeds total landing distance")
  func landingRun_neverExceedsTotalDistance() {
    let testCases: [(contamination: Contamination?, weight: Double, temp: Double)] = [
      (.waterOrSlush(depth: .init(value: 0.5, unit: .inches)), 6000, 20),
      (.slushOrWetSnow(depth: .init(value: 0.75, unit: .inches)), 5500, 10),
      (.drySnow, 5000, -5),
      (.compactSnow, 5500, -10),
      (nil, 6000, 15)  // Clean runway as control
    ]

    for testCase in testCases {
      let conditions = Helper.createTestConditions(temperature: testCase.temp)
      let config = Helper.createTestConfiguration(weight: testCase.weight)
      let runway = Helper.createTestRunway()
      let runwayInput = RunwayInput(from: runway, airport: runway.airport)

      let notam: NOTAMInput? =
        if let contamination = testCase.contamination {
          NOTAMInput(
            contaminationType: contamination.type,
            contaminationDepth: .init(value: contamination.depth ?? 0, unit: .meters),
            takeoffDistanceShortening: .init(value: 0, unit: .feet),
            landingDistanceShortening: .init(value: 0, unit: .feet),
            obstacleHeight: .init(value: 0, unit: .feet),
            obstacleDistance: .init(value: 0, unit: .nauticalMiles)
          )
        } else {
          nil
        }

      let model = TabularPerformanceModel(
        conditions: conditions,
        configuration: config,
        runway: runwayInput,
        notam: notam,
        aircraftType: .g1
      )

      if case .value(let run) = model.landingRunFt,
        case .value(let distance) = model.landingDistanceFt
      {
        PerformanceCase(for: model, aircraftType: .g1)
          .expect(
            run <= distance,
            "Landing run should not exceed total landing distance",
            results: ["landing run": run, "landing distance": distance]
          )
      }
    }
  }
}
