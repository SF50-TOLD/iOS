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

  @Test
  func `water contamination increases landing run - Tabular G1`() {
    let conditions = Helper.createTestConditions(temperature: 20)
    let config = Helper.createTestConfiguration(weight: 5000)
    let runway = Helper.createTestRunway()
    let runwayInput = RunwayInput(from: runway, airport: runway.airport, notam: nil)

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

  @Test
  func `slush contamination increases landing run - Tabular G2+`() {
    let conditions = Helper.createTestConditions(temperature: 20)
    let config = Helper.createTestConfiguration(weight: 5000)
    let runway = Helper.createTestRunway()
    let runwayInput = RunwayInput(from: runway, airport: runway.airport, notam: nil)

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

  @Test
  func `dry snow contamination increases landing run - Regression G1`() {
    let conditions = Helper.createTestConditions(temperature: -5)  // Cold for snow
    let config = Helper.createTestConfiguration(weight: 5500)
    let runway = Helper.createTestRunway()
    let runwayInput = RunwayInput(from: runway, airport: runway.airport, notam: nil)

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

  @Test
  func `compact snow contamination increases landing run - Regression G2+`() {
    let conditions = Helper.createTestConditions(temperature: -10)
    let config = Helper.createTestConfiguration(weight: 5000)
    let runway = Helper.createTestRunway()
    let runwayInput = RunwayInput(from: runway, airport: runway.airport, notam: nil)

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

  @Test
  func `water contamination increases total landing distance - Tabular G1`() {
    let conditions = Helper.createTestConditions(temperature: 20)
    let config = Helper.createTestConfiguration(weight: 5000)
    let runway = Helper.createTestRunway()
    let runwayInput = RunwayInput(from: runway, airport: runway.airport, notam: nil)

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

  @Test
  func `slush contamination increases total landing distance - Tabular G2+`() {
    let conditions = Helper.createTestConditions(temperature: 5)
    let config = Helper.createTestConfiguration(weight: 5500, flapSetting: .flaps100)
    let runway = Helper.createTestRunway()
    let runwayInput = RunwayInput(from: runway, airport: runway.airport, notam: nil)

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

    let slushContamination2 = Contamination.slushOrWetSnow(depth: .init(value: 0.5, unit: .inches))
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

  @Test
  func `dry snow contamination increases total landing distance - Regression G1`() {
    let conditions = Helper.createTestConditions(temperature: -5)
    let config = Helper.createTestConfiguration(weight: 5000)
    let runway = Helper.createTestRunway()
    let runwayInput = RunwayInput(from: runway, airport: runway.airport, notam: nil)

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

  @Test
  func `compact snow contamination increases total landing distance - Regression G2+`() {
    let conditions = Helper.createTestConditions(temperature: -10)
    let config = Helper.createTestConfiguration(weight: 5500)
    let runway = Helper.createTestRunway()
    let runwayInput = RunwayInput(from: runway, airport: runway.airport, notam: nil)

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

  @Test
  func `shallower water depth causes greater distance increase per AFM`() {
    let conditions = Helper.createTestConditions(temperature: 20)
    let config = Helper.createTestConfiguration(weight: 5000)
    let runway = Helper.createTestRunway()
    let runwayInput = RunwayInput(from: runway, airport: runway.airport, notam: nil)

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

    // Deep water (0.5 inches)
    let deepWaterContamination = Contamination.waterOrSlush(
      depth: .init(value: 0.5, unit: .inches)
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

  @Test
  func `contamination combined with headwind`() {
    let headwindConditions = Helper.createTestConditions(
      temperature: 20,
      windDirection: 360,
      windSpeed: 10
    )
    let config = Helper.createTestConfiguration(weight: 5000)
    let runway = Helper.createTestRunway(heading: 360)
    let runwayInput = RunwayInput(from: runway, airport: runway.airport, notam: nil)

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

  @Test
  func `contamination combined with uphill slope`() {
    let conditions = Helper.createTestConditions(temperature: 20)
    let config = Helper.createTestConfiguration(weight: 5000)
    let runway = Helper.createTestRunway(slope: 1.0)  // 1% uphill
    let runwayInput = RunwayInput(from: runway, airport: runway.airport, notam: nil)

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

  @Test
  func `wet runway contamination increases landing run by 15% - Tabular G2+`() {
    let conditions = Helper.createTestConditions(temperature: 20)
    let config = Helper.createTestConfiguration(weight: 5550)
    let runway = Helper.createTestRunway()
    let runwayInput = RunwayInput(from: runway, airport: runway.airport, notam: nil)

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

  @Test
  func `wet runway contamination increases landing run by 15% - Regression G2+`() {
    let conditions = Helper.createTestConditions(temperature: 20)
    let config = Helper.createTestConfiguration(weight: 5550)
    let runway = Helper.createTestRunway()
    let runwayInput = RunwayInput(from: runway, airport: runway.airport, notam: nil)

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

  @Test
  func `wet runway contamination has no effect on G1 - Tabular`() {
    let conditions = Helper.createTestConditions(temperature: 20)
    let config = Helper.createTestConfiguration(weight: 5550)
    let runway = Helper.createTestRunway()
    let runwayInput = RunwayInput(from: runway, airport: runway.airport, notam: nil)

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

  @Test
  func `wet runway contamination increases landing run by 15% - Regression G1`() {
    let conditions = Helper.createTestConditions(temperature: 20)
    let config = Helper.createTestConfiguration(weight: 5550)
    let runway = Helper.createTestRunway()
    let runwayInput = RunwayInput(from: runway, airport: runway.airport, notam: nil)

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

  @Test
  func `wet runway contamination increases total landing distance - G2+`() {
    let conditions = Helper.createTestConditions(temperature: 20)
    let config = Helper.createTestConfiguration(weight: 5550)
    let runway = Helper.createTestRunway()
    let runwayInput = RunwayInput(from: runway, airport: runway.airport, notam: nil)

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

  @Test
  func `landing run never exceeds total landing distance`() {
    let testCases: [(contamination: Contamination?, weight: Double, temp: Double)] = [
      (.waterOrSlush(depth: .init(value: 0.5, unit: .inches)), 6000, 20),
      (.slushOrWetSnow(depth: .init(value: 0.5, unit: .inches)), 5500, 10),
      (.drySnow, 5000, -5),
      (.compactSnow, 5500, -10),
      (nil, 6000, 15)  // Clean runway as control
    ]

    for testCase in testCases {
      let conditions = Helper.createTestConditions(temperature: testCase.temp)
      let config = Helper.createTestConfiguration(weight: testCase.weight)
      let runway = Helper.createTestRunway()
      let runwayInput = RunwayInput(from: runway, airport: runway.airport, notam: nil)

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

  // MARK: - Depths Outside the Tables

  /// ``Contamination/shallowestTabulatedDepth`` and ``Contamination/deepestTabulatedDepth`` state
  /// where the AFM's water and slush data stops, and the regression formulas' extrapolation
  /// ceiling is measured from them. Nothing else ties the two constants to the CSVs they
  /// describe, so this checks them against those: were they widened without the data widening
  /// too, the regression would extrapolate exactly as far past the fit as they claim is still
  /// inside it.
  @Test(arguments: [AircraftType.g1, .g2(updatedThrustSchedule: false), .g2Plus])
  func `the tabulated depth range matches the AFM tables`(aircraftType: AircraftType) {
    let loader = DataTableLoader(aircraftType: aircraftType),
      shallowest = Contamination.shallowestTabulatedDepth.converted(to: .inches).value,
      deepest = Contamination.deepestTabulatedDepth.converted(to: .inches).value

    for table in [loader.loadContaminationWaterData(), loader.loadContaminationSlushData()] {
      #expect(table.min(dimension: Self.depthDimension) == shallowest)
      #expect(table.max(dimension: Self.depthDimension) == deepest)
    }
  }

  /// A reading of water or slush no depth at all describes a runway with nothing on it, so it is
  /// rejected where the reading is parsed. Every reader then agrees: the runway row and the report
  /// write a clean runway, and both models compute one, instead of printing “Water/Slush 0″”
  /// beside a penalty for the shallowest depth the AFM tabulates.
  @Test
  func `a contaminant of no depth reads as a clean runway`() throws {
    for condition in DepthCondition.allCases {
      #expect(Contamination(type: condition.contamination(atDepthInches: 0).type, depth: 0) == nil)
    }

    let
      dryRun = try #require(Self.landingRunFt(contamination: nil, usingTabularData: true).nominal),
      zeroDepthRun = try #require(
        Self.landingRunFt(
          contamination: .waterOrSlush(depth: .init(value: 0, unit: .inches)),
          usingTabularData: true
        ).nominal
      )
    #expect(zeroDepthRun == dryRun)
  }

  /// The AFM tabulates water and slush from an eighth of an inch through half an inch and gives no
  /// distance outside that, so the tabular model reports the depth as offscale. Reading such a
  /// runway at the nearest depth the tables do hold would answer for a runway the AFM never
  /// covered; handing back the dry distance would be worse still, since the pilot has said there
  /// is water on it.
  @Test(arguments: DepthCondition.allCases)
  func `the tabular model reports a depth outside the AFM tables as offscale`(
    condition: DepthCondition
  ) throws {
    let dryRun = try #require(Self.landingRunFt(contamination: nil, usingTabularData: true).nominal)

    for depthInches in [0.05, 0.1] {
      let run = Self.landingRunFt(
        contamination: condition.contamination(atDepthInches: depthInches),
        usingTabularData: true
      )
      #expect(
        run == .offscaleLow,
        "\(depthInches)\u{2033} should read offscale low"
      )
      #expect(run.nominal != dryRun)
    }

    for depthInches in [0.6, 3.0] {
      #expect(
        Self.landingRunFt(
          contamination: condition.contamination(atDepthInches: depthInches),
          usingTabularData: true
        ) == .offscaleHigh,
        "\(depthInches)\u{2033} should read offscale high"
      )
    }
  }

  /// The regression formulas are fitted equations, so they answer past the depths the tables
  /// tabulate: shallower they converge on the tables’ own shallow-water worst case, which is
  /// both bounded and conservative, and deeper they hold up as far as the fit is extrapolated.
  /// Past that ceiling the answer is N/A.
  ///
  /// Across the tabulated depths the answer stays longer than the dry ground run and shortens as
  /// the contaminant deepens, the way the tables do. Past them the water formula carries that
  /// shortening below the dry run, which deep contaminant's displacement and spray drag make an
  /// answer rather than a failure; what the ceiling keeps out is a distance at or below zero.
  @Test(arguments: DepthCondition.allCases)
  func `the regression model extrapolates past the AFM tables and stops at the fit edge`(
    condition: DepthCondition
  ) throws {
    let dryRun = try #require(
      Self.landingRunFt(contamination: nil, usingTabularData: false).nominal
    )

    let shallowRun = try #require(
      Self.landingRunFt(
        contamination: condition.contamination(atDepthInches: 0.1),
        usingTabularData: false
      ).nominal
    )
    #expect(shallowRun > dryRun)

    let tabulatedDeepRun = try #require(
      Self.landingRunFt(
        contamination: condition.contamination(atDepthInches: 0.5),
        usingTabularData: false
      ).nominal
    )
    #expect(tabulatedDeepRun > dryRun)
    #expect(tabulatedDeepRun < shallowRun)

    let extrapolatedDeepRun = try #require(
      Self.landingRunFt(
        contamination: condition.contamination(atDepthInches: 0.875),
        usingTabularData: false
      ).nominal
    )
    #expect(extrapolatedDeepRun > 0)
    #expect(extrapolatedDeepRun < tabulatedDeepRun)

    for depthInches in [0.9, 3.0] {
      #expect(
        Self.landingRunFt(
          contamination: condition.contamination(atDepthInches: depthInches),
          usingTabularData: false
        ) == .notAvailable,
        "\(depthInches)\u{2033} should read not available"
      )
    }
  }
}

// MARK: - Helpers

extension ContaminationTests {

  /// The contaminant-depth axis of the AFM's water and slush tables, which are tabulated by dry
  /// ground run and then by depth.
  fileprivate static let depthDimension = 1

  /// The G1 landing ground run, in feet, over a runway in the given condition.
  fileprivate static func landingRunFt(
    contamination: Contamination?,
    usingTabularData: Bool
  ) -> Value<Double> {
    let runway = Helper.createTestRunway()
    let conditions = Helper.createTestConditions(temperature: 20),
      configuration = Helper.createTestConfiguration(weight: 5000),
      runwayInput = RunwayInput(from: runway, airport: runway.airport, notam: nil),
      notamInput = contamination.map(notam(for:))

    return usingTabularData
      ? TabularPerformanceModel(
        conditions: conditions,
        configuration: configuration,
        runway: runwayInput,
        notam: notamInput,
        aircraftType: .g1
      ).landingRunFt
      : RegressionPerformanceModel(
        conditions: conditions,
        configuration: configuration,
        runway: runwayInput,
        notam: notamInput,
        aircraftType: .g1
      ).landingRunFt
  }

  private static func notam(for contamination: Contamination) -> NOTAMInput {
    .init(
      contaminationType: contamination.type,
      contaminationDepth: .init(value: contamination.depth ?? 0, unit: .meters),
      takeoffDistanceShortening: .init(value: 0, unit: .feet),
      landingDistanceShortening: .init(value: 0, unit: .feet),
      obstacleHeight: .init(value: 0, unit: .feet),
      obstacleDistance: .init(value: 0, unit: .nauticalMiles)
    )
  }

  /// A runway condition the AFM tabulates by contaminant depth.
  enum DepthCondition: CaseIterable {
    case waterOrSlush
    case slushOrWetSnow

    func contamination(atDepthInches depthInches: Double) -> Contamination {
      let depth = Measurement(value: depthInches, unit: UnitLength.inches)
      return switch self {
        case .waterOrSlush: .waterOrSlush(depth: depth)
        case .slushOrWetSnow: .slushOrWetSnow(depth: depth)
      }
    }
  }
}
