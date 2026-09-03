import Foundation
import Testing

@testable import SF50_Shared

struct RegressionPerformanceModelG1Tests {

  // MARK: - Takeoff Ground Run Tests

  @Test
  func takeoffGroundRun_withinTolerance() throws {
    let csvURL = Bundle(for: BasePerformanceModel.self).resourceURL!
      .appending(component: "Data/g1/takeoff/ground run.csv")
    let dataTable = try DataTable(fileURL: csvURL)

    validateRegressionPredictions(
      dataTable,
      modelBuilder: { conditions, config, runway in
        RegressionPerformanceModel(
          conditions: conditions,
          configuration: config,
          runway: runway,
          notam: nil,
          aircraftType: .g1
        )
      },
      valueExtractor: { $0.takeoffRunFt },
      aircraftType: .g1,
      testName: "takeoffGroundRun"
    )
  }

  // MARK: - Takeoff Distance Tests

  @Test
  func takeoffDistance_withinTolerance() throws {
    let csvURL = Bundle(for: BasePerformanceModel.self).resourceURL!
      .appending(component: "Data/g1/takeoff/total distance.csv")
    let dataTable = try DataTable(fileURL: csvURL)

    validateRegressionPredictions(
      dataTable,
      modelBuilder: { conditions, config, runway in
        RegressionPerformanceModel(
          conditions: conditions,
          configuration: config,
          runway: runway,
          notam: nil,
          aircraftType: .g1
        )
      },
      valueExtractor: { $0.takeoffDistanceFt },
      aircraftType: .g1,
      testName: "takeoffDistance"
    )
  }

  // MARK: - Takeoff Climb Tests

  @Test
  func takeoffClimbGradient_withinTolerance() throws {
    let csvURL = Bundle(for: BasePerformanceModel.self).resourceURL!
      .appending(component: "Data/g1/takeoff climb/gradient.csv")
    let dataTable = try DataTable(fileURL: csvURL)

    validateRegressionPredictions(
      dataTable,
      modelBuilder: { conditions, config, runway in
        RegressionPerformanceModel(
          conditions: conditions,
          configuration: config,
          runway: runway,
          notam: nil,
          aircraftType: .g1
        )
      },
      valueExtractor: { $0.takeoffClimbGradientFtNM },
      aircraftType: .g1,
      testName: "takeoffClimbGradient"
    )
  }

  @Test
  func takeoffClimbRate_withinTolerance() throws {
    let csvURL = Bundle(for: BasePerformanceModel.self).resourceURL!
      .appending(component: "Data/g1/takeoff climb/rate.csv")
    let dataTable = try DataTable(fileURL: csvURL)

    validateRegressionPredictions(
      dataTable,
      modelBuilder: { conditions, config, runway in
        RegressionPerformanceModel(
          conditions: conditions,
          configuration: config,
          runway: runway,
          notam: nil,
          aircraftType: .g1
        )
      },
      valueExtractor: { $0.takeoffClimbRateFtMin },
      aircraftType: .g1,
      testName: "takeoffClimbRate"
    )
  }

  // MARK: - VREF Tests

  @Test
  func vref_withinTolerance() throws {
    // Test VREF values for different flap settings against DataTable values
    let baseURL = Bundle(for: BasePerformanceModel.self).resourceURL!
      .appending(component: "Data/g1/vref")

    let flapConfigs: [(file: String, flapSetting: FlapSetting)] = [
      ("50.csv", .flaps50),
      ("100.csv", .flaps100),
      ("up.csv", .flapsUp),
      ("50 ice.csv", .flaps50Ice),
      ("up ice.csv", .flapsUpIce)
    ]

    for config in flapConfigs {
      let csvURL = baseURL.appending(component: config.file)
      let dataTable = try DataTable(fileURL: csvURL)

      for row in dataTable.rows {
        let inputs = dataTable.inputs(from: row)
        let expected = dataTable.output(from: row)

        let weight = inputs[0]

        let conditions = Helper.createTestConditions()
        let testConfig = Helper.createTestConfiguration(
          weight: weight,
          flapSetting: config.flapSetting
        )
        let runway = Helper.createTestRunway()

        let model = RegressionPerformanceModel(
          conditions: conditions,
          configuration: testConfig,
          runway: RunwayInput(from: runway, airport: runway.airport),
          notam: nil,
          aircraftType: .g1
        )

        let result = model.VrefKts

        // Vref is a simple linear formula, not a regression model, so it must return a plain value
        guard case .value(let value) = result else {
          PerformanceCase(for: model, aircraftType: .g1)
            .fail("Vref should return a plain value, got \(result)", computing: "Vref")
          continue
        }

        // Check that the value is within 2% tolerance of expected
        #expect(value.isApproximatelyEqual(to: expected, relativeTolerance: 0.02))
      }
    }
  }

  // MARK: - Landing Ground Run Tests

  @Test
  func landingGroundRun_withinTolerance_flaps50() throws {
    let csvURL = Bundle(for: BasePerformanceModel.self).resourceURL!
      .appending(component: "Data/g1/landing/50/ground run.csv")
    let dataTable = try DataTable(fileURL: csvURL)

    validateRegressionPredictions(
      dataTable,
      configBuilder: { weight in
        Helper.createTestConfiguration(weight: weight, flapSetting: .flaps50)
      },
      modelBuilder: { conditions, config, runway in
        RegressionPerformanceModel(
          conditions: conditions,
          configuration: config,
          runway: runway,
          notam: nil,
          aircraftType: .g1
        )
      },
      valueExtractor: { $0.landingRunFt },
      aircraftType: .g1,
      testName: "landingGroundRun_flaps50"
    )
  }

  @Test
  func landingGroundRun_withinTolerance_flaps100() throws {
    let csvURL = Bundle(for: BasePerformanceModel.self).resourceURL!
      .appending(component: "Data/g1/landing/100/ground run.csv")
    let dataTable = try DataTable(fileURL: csvURL)

    validateRegressionPredictions(
      dataTable,
      configBuilder: { weight in
        Helper.createTestConfiguration(weight: weight, flapSetting: .flaps100)
      },
      modelBuilder: { conditions, config, runway in
        RegressionPerformanceModel(
          conditions: conditions,
          configuration: config,
          runway: runway,
          notam: nil,
          aircraftType: .g1
        )
      },
      valueExtractor: { $0.landingRunFt },
      aircraftType: .g1,
      testName: "landingGroundRun_flaps100"
    )
  }

  // MARK: - Landing Distance Tests

  @Test
  func landingDistance_withinTolerance_flaps50() throws {
    let csvURL = Bundle(for: BasePerformanceModel.self).resourceURL!
      .appending(component: "Data/g1/landing/50/total distance.csv")
    let dataTable = try DataTable(fileURL: csvURL)

    validateRegressionPredictions(
      dataTable,
      configBuilder: { weight in
        Helper.createTestConfiguration(weight: weight, flapSetting: .flaps50)
      },
      modelBuilder: { conditions, config, runway in
        RegressionPerformanceModel(
          conditions: conditions,
          configuration: config,
          runway: runway,
          notam: nil,
          aircraftType: .g1
        )
      },
      valueExtractor: { $0.landingDistanceFt },
      aircraftType: .g1,
      testName: "landingDistance_flaps50"
    )
  }

  @Test
  func landingDistance_withinTolerance_flaps100() throws {
    let csvURL = Bundle(for: BasePerformanceModel.self).resourceURL!
      .appending(component: "Data/g1/landing/100/total distance.csv")
    let dataTable = try DataTable(fileURL: csvURL)

    validateRegressionPredictions(
      dataTable,
      configBuilder: { weight in
        Helper.createTestConfiguration(weight: weight, flapSetting: .flaps100)
      },
      modelBuilder: { conditions, config, runway in
        RegressionPerformanceModel(
          conditions: conditions,
          configuration: config,
          runway: runway,
          notam: nil,
          aircraftType: .g1
        )
      },
      valueExtractor: { $0.landingDistanceFt },
      aircraftType: .g1,
      testName: "landingDistance_flaps100"
    )
  }

  // MARK: - Enroute Climb Tests - Normal

  @Test
  func enrouteClimbGradient_normal_withinTolerance() throws {
    let csvURL = Bundle(for: BasePerformanceModel.self).resourceURL!
      .appending(component: "Data/g1/enroute climb/normal/gradient.csv")
    let dataTable = try DataTable(fileURL: csvURL)

    validateRegressionPredictions(
      dataTable,
      inputExtractor: { inputs in (weight: inputs[2], altitude: inputs[0], temperature: inputs[1])
      },
      configBuilder: { weight in
        Helper.createTestConfiguration(weight: weight, iceProtection: false)
      },
      modelBuilder: { conditions, config, runway in
        RegressionPerformanceModel(
          conditions: conditions,
          configuration: config,
          runway: runway,
          notam: nil,
          aircraftType: .g1
        )
      },
      valueExtractor: { $0.enrouteClimbGradientFtNM },
      aircraftType: .g1,
      testName: "enrouteClimbGradient_normal"
    )
  }

  @Test
  func enrouteClimbRate_normal_withinTolerance() throws {
    let csvURL = Bundle(for: BasePerformanceModel.self).resourceURL!
      .appending(component: "Data/g1/enroute climb/normal/rate.csv")
    let dataTable = try DataTable(fileURL: csvURL)

    validateRegressionPredictions(
      dataTable,
      inputExtractor: { inputs in (weight: inputs[2], altitude: inputs[0], temperature: inputs[1])
      },
      configBuilder: { weight in
        Helper.createTestConfiguration(weight: weight, iceProtection: false)
      },
      modelBuilder: { conditions, config, runway in
        RegressionPerformanceModel(
          conditions: conditions,
          configuration: config,
          runway: runway,
          notam: nil,
          aircraftType: .g1
        )
      },
      valueExtractor: { $0.enrouteClimbRateFtMin },
      aircraftType: .g1,
      testName: "enrouteClimbRate_normal"
    )
  }

  @Test
  func enrouteClimbSpeed_normal_withinTolerance() throws {
    let csvURL = Bundle(for: BasePerformanceModel.self).resourceURL!
      .appending(component: "Data/g1/enroute climb/normal/speed.csv")
    let dataTable = try DataTable(fileURL: csvURL)

    validateRegressionPredictions(
      dataTable,
      inputExtractor: { inputs in (weight: inputs[2], altitude: inputs[0], temperature: inputs[1])
      },
      configBuilder: { weight in
        Helper.createTestConfiguration(weight: weight, iceProtection: false)
      },
      modelBuilder: { conditions, config, runway in
        RegressionPerformanceModel(
          conditions: conditions,
          configuration: config,
          runway: runway,
          notam: nil,
          aircraftType: .g1
        )
      },
      valueExtractor: { $0.enrouteClimbSpeedKIAS },
      aircraftType: .g1,
      testName: "enrouteClimbSpeed_normal"
    )
  }

  // MARK: - Enroute Climb Tests - Ice Contaminated

  @Test
  func enrouteClimbGradient_iceContaminated_withinTolerance() throws {
    let csvURL = Bundle(for: BasePerformanceModel.self).resourceURL!
      .appending(component: "Data/g1/enroute climb/ice contaminated/gradient.csv")
    let dataTable = try DataTable(fileURL: csvURL)

    validateRegressionPredictions(
      dataTable,
      inputExtractor: { inputs in (weight: inputs[2], altitude: inputs[0], temperature: inputs[1])
      },
      configBuilder: { weight in Helper.createTestConfiguration(weight: weight, iceProtection: true)
      },
      modelBuilder: { conditions, config, runway in
        RegressionPerformanceModel(
          conditions: conditions,
          configuration: config,
          runway: runway,
          notam: nil,
          aircraftType: .g1
        )
      },
      valueExtractor: { $0.enrouteClimbGradientFtNM },
      aircraftType: .g1,
      testName: "enrouteClimbGradient_iceContaminated"
    )
  }

  @Test
  func enrouteClimbRate_iceContaminated_withinTolerance() throws {
    let csvURL = Bundle(for: BasePerformanceModel.self).resourceURL!
      .appending(component: "Data/g1/enroute climb/ice contaminated/rate.csv")
    let dataTable = try DataTable(fileURL: csvURL)

    validateRegressionPredictions(
      dataTable,
      inputExtractor: { inputs in (weight: inputs[2], altitude: inputs[0], temperature: inputs[1])
      },
      configBuilder: { weight in Helper.createTestConfiguration(weight: weight, iceProtection: true)
      },
      modelBuilder: { conditions, config, runway in
        RegressionPerformanceModel(
          conditions: conditions,
          configuration: config,
          runway: runway,
          notam: nil,
          aircraftType: .g1
        )
      },
      valueExtractor: { $0.enrouteClimbRateFtMin },
      aircraftType: .g1,
      testName: "enrouteClimbRate_iceContaminated"
    )
  }

  @Test
  func enrouteClimbSpeed_iceContaminated_withinTolerance() throws {
    let csvURL = Bundle(for: BasePerformanceModel.self).resourceURL!
      .appending(component: "Data/g1/enroute climb/ice contaminated/speed.csv")
    let dataTable = try DataTable(fileURL: csvURL)

    validateRegressionPredictions(
      dataTable,
      inputExtractor: { inputs in (weight: inputs[2], altitude: inputs[0], temperature: inputs[1])
      },
      configBuilder: { weight in Helper.createTestConfiguration(weight: weight, iceProtection: true)
      },
      modelBuilder: { conditions, config, runway in
        RegressionPerformanceModel(
          conditions: conditions,
          configuration: config,
          runway: runway,
          notam: nil,
          aircraftType: .g1
        )
      },
      valueExtractor: { $0.enrouteClimbSpeedKIAS },
      aircraftType: .g1,
      testName: "enrouteClimbSpeed_iceContaminated"
    )
  }

  // MARK: - Wind Adjustment Tests

  @Test
  func takeoffRun_headwindAdjustment_regression() {
    // Test with 10 kt headwind for regression model
    let conditionsNoWind = Helper.createTestConditions(temperature: 20)
    let conditionsHeadwind = Helper.createTestConditions(
      temperature: 20,
      windDirection: 360,
      windSpeed: 10
    )
    let config = Helper.createTestConfiguration()
    let runway = Helper.createTestRunway(heading: 360)

    let modelNoWind = RegressionPerformanceModel(
      conditions: conditionsNoWind,
      configuration: config,
      runway: RunwayInput(from: runway, airport: runway.airport),
      notam: nil,
      aircraftType: .g1
    )

    let modelHeadwind = RegressionPerformanceModel(
      conditions: conditionsHeadwind,
      configuration: config,
      runway: RunwayInput(from: runway, airport: runway.airport),
      notam: nil,
      aircraftType: .g1
    )

    // Extract values from the results (which may include uncertainty)
    let noWindValue: Double
    let headwindValue: Double

    switch modelNoWind.takeoffRunFt {
      case .value(let val), .valueWithUncertainty(let val, _):
        noWindValue = val
      default:
        PerformanceCase(for: modelNoWind, aircraftType: .g1)
          .fail(
            "Expected a no-wind takeoff run, got \(modelNoWind.takeoffRunFt)",
            computing: "no-wind takeoff run"
          )
        return
    }

    switch modelHeadwind.takeoffRunFt {
      case .value(let val), .valueWithUncertainty(let val, _):
        headwindValue = val
      default:
        PerformanceCase(for: modelHeadwind, aircraftType: .g1)
          .fail(
            "Expected a headwind takeoff run, got \(modelHeadwind.takeoffRunFt)",
            computing: "headwind takeoff run"
          )
        return
    }

    // Headwind should reduce takeoff run
    #expect(headwindValue < noWindValue)
  }

  @Test
  func landingDistance_unpavedAdjustment_regression() {
    // Test unpaved runway adjustment for regression model
    let conditions = Helper.createTestConditions(temperature: 20)
    let config = Helper.createTestConfiguration()
    let runwayPaved = Helper.createTestRunway(surfaceType: .paved)
    let runwayUnpaved = Helper.createTestRunway(surfaceType: .turf)

    let modelPaved = RegressionPerformanceModel(
      conditions: conditions,
      configuration: config,
      runway: RunwayInput(from: runwayPaved, airport: runwayPaved.airport),
      notam: nil,
      aircraftType: .g1
    )

    let modelUnpaved = RegressionPerformanceModel(
      conditions: conditions,
      configuration: config,
      runway: RunwayInput(from: runwayUnpaved, airport: runwayUnpaved.airport),
      notam: nil,
      aircraftType: .g1
    )

    // Extract values from the results (which may include uncertainty)
    let pavedValue: Double
    let unpavedValue: Double

    switch modelPaved.landingDistanceFt {
      case .value(let val), .valueWithUncertainty(let val, _):
        pavedValue = val
      default:
        PerformanceCase(for: modelPaved, aircraftType: .g1)
          .fail(
            "Expected a paved landing distance, got \(modelPaved.landingDistanceFt)",
            computing: "paved landing distance"
          )
        return
    }

    switch modelUnpaved.landingDistanceFt {
      case .value(let val), .valueWithUncertainty(let val, _):
        unpavedValue = val
      default:
        PerformanceCase(for: modelUnpaved, aircraftType: .g1)
          .fail(
            "Expected a unpaved landing distance, got \(modelUnpaved.landingDistanceFt)",
            computing: "unpaved landing distance"
          )
        return
    }

    // Unpaved landing distance should be greater than paved
    #expect(unpavedValue > pavedValue)
    // Unpaved factor is typically 20% increase
    #expect(unpavedValue.isApproximatelyEqual(to: pavedValue * 1.2, relativeTolerance: 0.01))
  }

  // MARK: - Go-Around Climb Gradient Tests

  @Test
  func meetsGoAroundClimbGradient_matchesTabularOffscale() {
    // Test that regression model's meetsGoAroundClimbGradient aligns with
    // tabular model's offscale behavior for landing distance

    let testCases:
      [(
        weight: Double, altitude: Double, temperature: Double, flapSetting: FlapSetting,
        expectedMeets: Bool
      )] = [
        // Cases where tabular model should NOT be offscale (gradient should be met)
        // Using only exact data points (weights 4500 or 5550, altitudes in 1000 ft increments, temps in 10°C increments)
        (4500, 0, 20, .flaps100, true),
        (4500, 2000, 20, .flaps100, true),
        (4500, 5000, 10, .flaps100, true),
        (5550, 0, 20, .flaps100, true),
        (5550, 3000, 0, .flaps100, true),

        // Cases near the edge but still within data bounds
        (5550, 7000, 20, .flaps100, true),  // Max temp at 7000 ft is 20°C for weight 5550
        (5550, 8000, 20, .flaps100, true),  // Max temp at 8000 ft is 20°C for weight 5550
        (4500, 7000, 30, .flaps100, true)  // Weight 4500 has data at 7000 ft, 30°C
      ]

    for testCase in testCases {
      let conditions = Helper.createTestConditions(temperature: testCase.temperature)
      let config = Helper.createTestConfiguration(
        weight: testCase.weight,
        flapSetting: testCase.flapSetting
      )
      let runway = Helper.createTestRunway(elevation: testCase.altitude)

      // Test regression model
      let regressionModel = RegressionPerformanceModel(
        conditions: conditions,
        configuration: config,
        runway: RunwayInput(from: runway, airport: runway.airport),
        notam: nil,
        aircraftType: .g1
      )

      let regressionResult = regressionModel.meetsGoAroundClimbGradient

      guard case .value(let meetsGradient) = regressionResult else {
        PerformanceCase(for: regressionModel, aircraftType: .g1)
          .fail(
            "Expected .value for regression model at weight: \(testCase.weight), altitude: \(testCase.altitude), temp: \(testCase.temperature)",
            computing: "regression go-around climb gradient"
          )
        continue
      }

      #expect(
        meetsGradient == testCase.expectedMeets,
        "Weight: \(testCase.weight), Alt: \(testCase.altitude), Temp: \(testCase.temperature), Flaps: \(testCase.flapSetting) - Expected: \(testCase.expectedMeets), Got: \(meetsGradient)"
      )

      // Also verify against tabular model
      let tabularModel = TabularPerformanceModel(
        conditions: conditions,
        configuration: config,
        runway: RunwayInput(from: runway, airport: runway.airport),
        notam: nil,
        aircraftType: .g1
      )

      let tabularLandingDistance = tabularModel.landingDistanceFt
      let tabularGoAround = tabularModel.meetsGoAroundClimbGradient

      // When tabular landing distance is offscale high, go-around should be false
      if case .offscaleHigh = tabularLandingDistance {
        guard case .value(false) = tabularGoAround else {
          PerformanceCase(for: tabularModel, aircraftType: .g1)
            .fail(
              "Tabular model should return false for go-around when landing distance is offscale high",
              computing: "tabular go-around climb gradient"
            )
          continue
        }
      }

      // Regression and tabular should generally agree
      if case .value(let tabularMeets) = tabularGoAround {
        #expect(
          meetsGradient == tabularMeets,
          "Regression and tabular models disagree at weight: \(testCase.weight), altitude: \(testCase.altitude), temp: \(testCase.temperature)"
        )
      }
    }
  }

  @Test
  func meetsGoAroundClimbGradient_boundaryConditions() {
    // Test boundary conditions for the go-around climb gradient

    // Test at minimum weight
    let minWeightConditions = Helper.createTestConditions(temperature: 15)
    let minWeightConfig = Helper.createTestConfiguration(weight: 4500, flapSetting: .flaps100)
    let minWeightRunway = Helper.createTestRunway(elevation: 2000)

    let minWeightModel = RegressionPerformanceModel(
      conditions: minWeightConditions,
      configuration: minWeightConfig,
      runway: RunwayInput(from: minWeightRunway, airport: minWeightRunway.airport),
      notam: nil,
      aircraftType: .g1
    )

    guard case .value(let minWeightMeets) = minWeightModel.meetsGoAroundClimbGradient else {
      PerformanceCase(for: minWeightModel, aircraftType: .g1)
        .fail(
          "Expected .value for minimum weight test",
          computing: "minimum weight go-around climb gradient"
        )
      return
    }
    #expect(
      minWeightMeets == true,
      "Should meet gradient at minimum weight with moderate conditions"
    )

    // Test at maximum weight with challenging conditions
    let maxWeightConditions = Helper.createTestConditions(temperature: 45)
    let maxWeightConfig = Helper.createTestConfiguration(weight: 6000, flapSetting: .flaps100)
    let maxWeightRunway = Helper.createTestRunway(elevation: 9000)

    let maxWeightModel = RegressionPerformanceModel(
      conditions: maxWeightConditions,
      configuration: maxWeightConfig,
      runway: RunwayInput(from: maxWeightRunway, airport: maxWeightRunway.airport),
      notam: nil,
      aircraftType: .g1
    )

    guard case .value(let maxWeightMeets) = maxWeightModel.meetsGoAroundClimbGradient else {
      PerformanceCase(for: maxWeightModel, aircraftType: .g1)
        .fail(
          "Expected .value for maximum weight test",
          computing: "maximum weight go-around climb gradient"
        )
      return
    }
    #expect(
      maxWeightMeets == false,
      "Should not meet gradient at maximum weight with challenging conditions"
    )
  }
}
