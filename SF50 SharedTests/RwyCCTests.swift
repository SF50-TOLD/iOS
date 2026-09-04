import Foundation
import RealModule
import Testing

@testable import SF50_Shared

/// Tests for RwyCC (Runway Condition Code) landing distance factors per AC 91-79B.
struct RwyCCTests {

  // MARK: - RwyCC LDF Lookup

  @Test(
    "RwyCC LDF values match CSV data for smooth surface",
    arguments: [
      (code: UInt8(6), expected: 1.67),
      (code: UInt8(5), expected: 2.60),
      (code: UInt8(4), expected: 2.80),
      (code: UInt8(3), expected: 3.20),
      (code: UInt8(2), expected: 4.00),
      (code: UInt8(1), expected: 5.10)
    ] as [(code: UInt8, expected: Double)]
  )
  func rwyCCLDF_smoothSurface(code: UInt8, expected: Double) {
    let calculator = ContaminationCalculator(aircraftType: .g1)
    let ldf = calculator.rwyCCLandingDistanceFactor(code: code, isGroovedPFC: false)
    #expect(ldf == expected)
  }

  @Test(
    "RwyCC LDF values match CSV data for grooved surface",
    arguments: [
      (code: UInt8(6), expected: 1.67),
      (code: UInt8(5), expected: 2.30),
      (code: UInt8(4), expected: 2.80),
      (code: UInt8(3), expected: 3.20),
      (code: UInt8(2), expected: 4.00),
      (code: UInt8(1), expected: 5.10)
    ] as [(code: UInt8, expected: Double)]
  )
  func rwyCCLDF_groovedSurface(code: UInt8, expected: Double) {
    let calculator = ContaminationCalculator(aircraftType: .g1)
    let ldf = calculator.rwyCCLandingDistanceFactor(code: code, isGroovedPFC: true)
    #expect(ldf == expected)
  }

  @Test("RwyCC 5 differs between grooved (2.30) and smooth (2.60)")
  func rwyCCCode5_differsForGroovedVsSmooth() {
    let calculator = ContaminationCalculator(aircraftType: .g1)
    let groovedLDF = calculator.rwyCCLandingDistanceFactor(code: 5, isGroovedPFC: true)
    let smoothLDF = calculator.rwyCCLandingDistanceFactor(code: 5, isGroovedPFC: false)
    #expect(groovedLDF == 2.30)
    #expect(smoothLDF == 2.60)
  }

  // MARK: - RwyCC Applies LDF to Landing Run

  @Test("RwyCC applies LDF to landing run - Tabular G1")
  func rwyCCAppliesLDFToLandingRun_tabularG1() {
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

    let rwyCCContamination = Contamination.rwyCC(3)
    let rwyCCNotam = NOTAMInput(
      contaminationType: rwyCCContamination.type,
      contaminationDepth: .init(value: 0, unit: .meters),
      rwyCC: rwyCCContamination.rwyCC,
      takeoffDistanceShortening: .init(value: 0, unit: .feet),
      landingDistanceShortening: .init(value: 0, unit: .feet),
      obstacleHeight: .init(value: 0, unit: .feet),
      obstacleDistance: .init(value: 0, unit: .nauticalMiles)
    )

    let rwyCCModel = TabularPerformanceModel(
      conditions: conditions,
      configuration: config,
      runway: runwayInput,
      notam: rwyCCNotam,
      aircraftType: .g1
    )

    guard case .value(let cleanRun) = cleanModel.landingRunFt else {
      PerformanceCase(for: cleanModel, aircraftType: .g1)
        .fail(
          "Expected a clean landing run, got \(cleanModel.landingRunFt)",
          computing: "clean landing run"
        )
      return
    }
    guard case .value(let rwyCCRun) = rwyCCModel.landingRunFt else {
      PerformanceCase(for: rwyCCModel, aircraftType: .g1)
        .fail(
          "Expected a RwyCC landing run, got \(rwyCCModel.landingRunFt)",
          computing: "RwyCC landing run"
        )
      return
    }

    // RwyCC 3 smooth → LDF 3.20
    let ratio = rwyCCRun / cleanRun
    #expect(
      ratio.isApproximatelyEqual(to: 3.20, relativeTolerance: 0.02),
      "RwyCC 3 should multiply landing run by 3.20"
    )
  }

  // MARK: - RwyCC Applies LDF to Total Landing Distance

  @Test("RwyCC applies LDF to total landing distance - Tabular G1")
  func rwyCCAppliesLDF_tabularG1() {
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

    guard case .value(let cleanDistance) = cleanModel.landingDistanceFt else {
      PerformanceCase(for: cleanModel, aircraftType: .g1)
        .fail("Expected clean landing distance", computing: "clean landing distance")
      return
    }

    // RwyCC 3 smooth → LDF 3.20
    let rwyCCContamination = Contamination.rwyCC(3)
    let rwyCCNotam = NOTAMInput(
      contaminationType: rwyCCContamination.type,
      contaminationDepth: .init(value: 0, unit: .meters),
      rwyCC: rwyCCContamination.rwyCC,
      takeoffDistanceShortening: .init(value: 0, unit: .feet),
      landingDistanceShortening: .init(value: 0, unit: .feet),
      obstacleHeight: .init(value: 0, unit: .feet),
      obstacleDistance: .init(value: 0, unit: .nauticalMiles)
    )

    let rwyCCModel = TabularPerformanceModel(
      conditions: conditions,
      configuration: config,
      runway: runwayInput,
      notam: rwyCCNotam,
      aircraftType: .g1
    )

    guard case .value(let rwyCCDistance) = rwyCCModel.landingDistanceFt else {
      PerformanceCase(for: rwyCCModel, aircraftType: .g1)
        .fail("Expected RwyCC landing distance", computing: "RwyCC landing distance")
      return
    }

    // The model's landingDistanceFt is unfactored (safety factor applied at ViewModel).
    // RwyCC distance = base * LDF; clean distance = base * 1.0.
    // So ratio of rwyCCDistance/cleanDistance ≈ LDF = 3.20
    let ratio = rwyCCDistance / cleanDistance
    #expect(
      ratio.isApproximatelyEqual(to: 3.20, relativeTolerance: 0.02),
      "RwyCC 3 should multiply base distance by 3.20"
    )
  }

  @Test("RwyCC 6 applies LDF 1.67 to unfactored base distance")
  func rwyCCCode6_appliesLDF() {
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

    // RwyCC 6 → LDF 1.67
    let rwyCC6 = Contamination.rwyCC(6)
    let rwyCC6Notam = NOTAMInput(
      contaminationType: rwyCC6.type,
      contaminationDepth: .init(value: 0, unit: .meters),
      rwyCC: rwyCC6.rwyCC,
      takeoffDistanceShortening: .init(value: 0, unit: .feet),
      landingDistanceShortening: .init(value: 0, unit: .feet),
      obstacleHeight: .init(value: 0, unit: .feet),
      obstacleDistance: .init(value: 0, unit: .nauticalMiles)
    )

    let rwyCC6Model = TabularPerformanceModel(
      conditions: conditions,
      configuration: config,
      runway: runwayInput,
      notam: rwyCC6Notam,
      aircraftType: .g1
    )

    guard case .value(let cleanDistance) = cleanModel.landingDistanceFt else {
      PerformanceCase(for: cleanModel, aircraftType: .g1)
        .fail(
          "Expected a clean landing distance, got \(cleanModel.landingDistanceFt)",
          computing: "clean landing distance"
        )
      return
    }
    guard case .value(let rwyCC6Distance) = rwyCC6Model.landingDistanceFt else {
      PerformanceCase(for: rwyCC6Model, aircraftType: .g1)
        .fail(
          "Expected a RwyCC 6 landing distance, got \(rwyCC6Model.landingDistanceFt)",
          computing: "RwyCC 6 landing distance"
        )
      return
    }

    // Model outputs unfactored distance; RwyCC 6 applies LDF 1.67 to the base.
    // So rwyCC6Distance ≈ cleanDistance * 1.67
    let ratio = rwyCC6Distance / cleanDistance
    #expect(
      ratio.isApproximatelyEqual(to: 1.67, relativeTolerance: 0.01),
      "RwyCC 6 (LDF 1.67) should be 1.67x the unfactored clean distance"
    )
  }

  // MARK: - RwyCC with Wind

  @Test("RwyCC landing distance includes headwind adjustment")
  func rwyCCLandingDistance_includesHeadwindAdjustment() {
    let noWindConditions = Helper.createTestConditions(temperature: 20)
    let headwindConditions = Helper.createTestConditions(
      temperature: 20,
      windDirection: 360,
      windSpeed: 15
    )
    let config = Helper.createTestConfiguration(weight: 5000)
    let runway = Helper.createTestRunway(heading: 360)
    let runwayInput = RunwayInput(from: runway, airport: runway.airport)

    let rwyCC3 = Contamination.rwyCC(3)
    let rwyCCNotam = NOTAMInput(
      contaminationType: rwyCC3.type,
      contaminationDepth: .init(value: 0, unit: .meters),
      rwyCC: rwyCC3.rwyCC,
      takeoffDistanceShortening: .init(value: 0, unit: .feet),
      landingDistanceShortening: .init(value: 0, unit: .feet),
      obstacleHeight: .init(value: 0, unit: .feet),
      obstacleDistance: .init(value: 0, unit: .nauticalMiles)
    )

    let noWindModel = TabularPerformanceModel(
      conditions: noWindConditions,
      configuration: config,
      runway: runwayInput,
      notam: rwyCCNotam,
      aircraftType: .g1
    )

    let headwindModel = TabularPerformanceModel(
      conditions: headwindConditions,
      configuration: config,
      runway: runwayInput,
      notam: rwyCCNotam,
      aircraftType: .g1
    )

    guard case .value(let noWindDistance) = noWindModel.landingDistanceFt else {
      PerformanceCase(for: noWindModel, aircraftType: .g1)
        .fail(
          "Expected a no-wind landing distance, got \(noWindModel.landingDistanceFt)",
          computing: "no-wind landing distance"
        )
      return
    }
    guard case .value(let headwindDistance) = headwindModel.landingDistanceFt else {
      PerformanceCase(for: headwindModel, aircraftType: .g1)
        .fail(
          "Expected a headwind landing distance, got \(headwindModel.landingDistanceFt)",
          computing: "headwind landing distance"
        )
      return
    }

    #expect(
      headwindDistance < noWindDistance,
      "Headwind should reduce RwyCC landing distance"
    )
  }

  // MARK: - RwyCC with Turf

  @Test("RwyCC landing distance includes unpaved adjustment for turf runway")
  func rwyCCLandingDistance_includesUnpavedAdjustment() {
    let conditions = Helper.createTestConditions(temperature: 20)
    let config = Helper.createTestConfiguration(weight: 5000)
    let pavedRunway = Helper.createTestRunway(surfaceType: .paved)
    let turfRunway = Helper.createTestRunway(surfaceType: .turf)
    let pavedInput = RunwayInput(from: pavedRunway, airport: pavedRunway.airport)
    let turfInput = RunwayInput(from: turfRunway, airport: turfRunway.airport)

    let rwyCC4 = Contamination.rwyCC(4)
    let rwyCCNotam = NOTAMInput(
      contaminationType: rwyCC4.type,
      contaminationDepth: .init(value: 0, unit: .meters),
      rwyCC: rwyCC4.rwyCC,
      takeoffDistanceShortening: .init(value: 0, unit: .feet),
      landingDistanceShortening: .init(value: 0, unit: .feet),
      obstacleHeight: .init(value: 0, unit: .feet),
      obstacleDistance: .init(value: 0, unit: .nauticalMiles)
    )

    let pavedModel = TabularPerformanceModel(
      conditions: conditions,
      configuration: config,
      runway: pavedInput,
      notam: rwyCCNotam,
      aircraftType: .g1
    )

    let turfModel = TabularPerformanceModel(
      conditions: conditions,
      configuration: config,
      runway: turfInput,
      notam: rwyCCNotam,
      aircraftType: .g1
    )

    guard case .value(let pavedDistance) = pavedModel.landingDistanceFt else {
      PerformanceCase(for: pavedModel, aircraftType: .g1)
        .fail(
          "Expected a paved landing distance, got \(pavedModel.landingDistanceFt)",
          computing: "paved landing distance"
        )
      return
    }
    guard case .value(let turfDistance) = turfModel.landingDistanceFt else {
      PerformanceCase(for: turfModel, aircraftType: .g1)
        .fail(
          "Expected a turf landing distance, got \(turfModel.landingDistanceFt)",
          computing: "turf landing distance"
        )
      return
    }

    #expect(
      turfDistance > pavedDistance,
      "Turf runway should increase RwyCC landing distance"
    )
  }

  // MARK: - RwyCC in Regression Model

  @Test("RwyCC applies LDF in regression model - G1")
  func rwyCCAppliesLDF_regressionG1() {
    let conditions = Helper.createTestConditions(temperature: 20)
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

    let rwyCC2 = Contamination.rwyCC(2)
    let rwyCCNotam = NOTAMInput(
      contaminationType: rwyCC2.type,
      contaminationDepth: .init(value: 0, unit: .meters),
      rwyCC: rwyCC2.rwyCC,
      takeoffDistanceShortening: .init(value: 0, unit: .feet),
      landingDistanceShortening: .init(value: 0, unit: .feet),
      obstacleHeight: .init(value: 0, unit: .feet),
      obstacleDistance: .init(value: 0, unit: .nauticalMiles)
    )

    let rwyCCModel = RegressionPerformanceModel(
      conditions: conditions,
      configuration: config,
      runway: runwayInput,
      notam: rwyCCNotam,
      aircraftType: .g1
    )

    guard case .valueWithUncertainty(let cleanDistance, _) = cleanModel.landingDistanceFt else {
      PerformanceCase(for: cleanModel, aircraftType: .g1)
        .fail(
          "Expected a clean landing distance, got \(cleanModel.landingDistanceFt)",
          computing: "clean landing distance"
        )
      return
    }
    guard case .valueWithUncertainty(let rwyCCDistance, _) = rwyCCModel.landingDistanceFt else {
      PerformanceCase(for: rwyCCModel, aircraftType: .g1)
        .fail(
          "Expected a RwyCC landing distance, got \(rwyCCModel.landingDistanceFt)",
          computing: "RwyCC landing distance"
        )
      return
    }

    // Model outputs unfactored distance; RwyCC 2 applies LDF 4.00 to the base.
    let ratio = rwyCCDistance / cleanDistance
    #expect(
      ratio.isApproximatelyEqual(to: 4.00, relativeTolerance: 0.02),
      "RwyCC 2 should multiply base distance by 4.00"
    )
  }
}
