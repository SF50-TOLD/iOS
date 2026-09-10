import Foundation
import Testing

@testable import SF50_Shared

@Suite
struct `Regression Model Offscale Detection` {

  private static func model(temperature: Double, iceProtection: Bool)
    -> RegressionPerformanceModel
  {
    let runway = Helper.createTestRunway()
    return RegressionPerformanceModel(
      conditions: Helper.createTestConditions(temperature: temperature),
      configuration: Helper.createTestConfiguration(
        weight: 5200,
        iceProtection: iceProtection
      ),
      runway: RunwayInput(from: runway, airport: runway.airport, notam: nil),
      notam: nil,
      aircraftType: .g1
    )
  }

  // MARK: - Landing Weight Tests

  @Test
  func `G1 landing weight below minimum sets landingInputsOffscaleLow flag`() throws {
    let conditions = Helper.createTestConditions(temperature: 15)
    let config = Helper.createTestConfiguration(weight: 3550)  // Below 4500 lbs minimum
    let runway = Helper.createTestRunway()
    let runwayInput = RunwayInput(from: runway, airport: runway.airport, notam: nil)

    let model = RegressionPerformanceModel(
      conditions: conditions,
      configuration: config,
      runway: runwayInput,
      notam: nil,
      aircraftType: .g1
    )

    // Regression models should still return computed values, not .offscaleLow
    switch model.landingRunFt {
      case .value, .valueWithUncertainty:
        break  // Expected
      case .offscaleLow, .offscaleHigh, .notAvailable, .invalid, .notAuthorized:
        PerformanceCase(for: model, aircraftType: .g1)
          .fail(
            "Expected a computed value, got \(model.landingRunFt)",
            computing: "landing run"
          )
    }

    // But the flag should be set
    #expect(model.landingInputsOffscaleLow == true)
    #expect(model.landingInputsOffscaleHigh == false)
  }

  @Test
  func `G1 landing weight above maximum sets landingInputsOffscaleHigh flag`() throws {
    let conditions = Helper.createTestConditions(temperature: 15)
    let config = Helper.createTestConfiguration(weight: 5650)  // Above 5550 lbs maximum
    let runway = Helper.createTestRunway()
    let runwayInput = RunwayInput(from: runway, airport: runway.airport, notam: nil)

    let model = RegressionPerformanceModel(
      conditions: conditions,
      configuration: config,
      runway: runwayInput,
      notam: nil,
      aircraftType: .g1
    )

    // Regression models should still return computed values, not .offscaleHigh
    switch model.landingRunFt {
      case .value, .valueWithUncertainty:
        break  // Expected
      case .offscaleLow, .offscaleHigh, .notAvailable, .invalid, .notAuthorized:
        PerformanceCase(for: model, aircraftType: .g1)
          .fail(
            "Expected a computed value, got \(model.landingRunFt)",
            computing: "landing run"
          )
    }

    // But the flag should be set
    #expect(model.landingInputsOffscaleLow == false)
    #expect(model.landingInputsOffscaleHigh == true)
  }

  @Test
  func `G2+ landing weight below minimum sets landingInputsOffscaleLow flag`() throws {
    let conditions = Helper.createTestConditions(temperature: 15)
    let config = Helper.createTestConfiguration(weight: 4000)  // Below 4500 lbs minimum
    let runway = Helper.createTestRunway()
    let runwayInput = RunwayInput(from: runway, airport: runway.airport, notam: nil)

    let model = RegressionPerformanceModel(
      conditions: conditions,
      configuration: config,
      runway: runwayInput,
      notam: nil,
      aircraftType: .g1
    )

    // Regression models should still return computed values
    switch model.landingRunFt {
      case .value, .valueWithUncertainty:
        break
      case .offscaleLow, .offscaleHigh, .notAvailable, .invalid, .notAuthorized:
        PerformanceCase(for: model, aircraftType: .g1)
          .fail(
            "Expected a computed value, got \(model.landingRunFt)",
            computing: "landing run"
          )
    }

    #expect(model.landingInputsOffscaleLow == true)
    #expect(model.landingInputsOffscaleHigh == false)
  }

  @Test
  func `G2+ landing weight above maximum sets landingInputsOffscaleHigh flag`() throws {
    let conditions = Helper.createTestConditions(temperature: 15)
    let config = Helper.createTestConfiguration(weight: 5700)  // Above 5550 lbs maximum
    let runway = Helper.createTestRunway()
    let runwayInput = RunwayInput(from: runway, airport: runway.airport, notam: nil)

    let model = RegressionPerformanceModel(
      conditions: conditions,
      configuration: config,
      runway: runwayInput,
      notam: nil,
      aircraftType: .g1
    )

    // Regression models should still return computed values
    switch model.landingRunFt {
      case .value, .valueWithUncertainty:
        break
      case .offscaleLow, .offscaleHigh, .notAvailable, .invalid, .notAuthorized:
        PerformanceCase(for: model, aircraftType: .g1)
          .fail(
            "Expected a computed value, got \(model.landingRunFt)",
            computing: "landing run"
          )
    }

    #expect(model.landingInputsOffscaleLow == false)
    #expect(model.landingInputsOffscaleHigh == true)
  }

  // MARK: - Takeoff Weight Tests

  @Test
  func `G1 takeoff weight below minimum sets takeoffInputsOffscaleLow flag`() throws {
    let conditions = Helper.createTestConditions(temperature: 15)
    let config = Helper.createTestConfiguration(weight: 4800)  // Below 5000 lbs minimum
    let runway = Helper.createTestRunway()
    let runwayInput = RunwayInput(from: runway, airport: runway.airport, notam: nil)

    let model = RegressionPerformanceModel(
      conditions: conditions,
      configuration: config,
      runway: runwayInput,
      notam: nil,
      aircraftType: .g1
    )

    switch model.takeoffRunFt {
      case .value, .valueWithUncertainty:
        break
      case .offscaleLow, .offscaleHigh, .notAvailable, .invalid, .notAuthorized:
        PerformanceCase(for: model, aircraftType: .g1)
          .fail(
            "Expected a computed value, got \(model.takeoffRunFt)",
            computing: "takeoff run"
          )
    }

    #expect(model.takeoffInputsOffscaleLow == true)
    #expect(model.takeoffInputsOffscaleHigh == false)
  }

  @Test
  func `G1 takeoff weight above maximum sets takeoffInputsOffscaleHigh flag`() throws {
    let conditions = Helper.createTestConditions(temperature: 15)
    let config = Helper.createTestConfiguration(weight: 6100)  // Above 6000 lbs maximum
    let runway = Helper.createTestRunway()
    let runwayInput = RunwayInput(from: runway, airport: runway.airport, notam: nil)

    let model = RegressionPerformanceModel(
      conditions: conditions,
      configuration: config,
      runway: runwayInput,
      notam: nil,
      aircraftType: .g1
    )

    switch model.takeoffRunFt {
      case .value, .valueWithUncertainty:
        break
      case .offscaleLow, .offscaleHigh, .notAvailable, .invalid, .notAuthorized:
        PerformanceCase(for: model, aircraftType: .g1)
          .fail(
            "Expected a computed value, got \(model.takeoffRunFt)",
            computing: "takeoff run"
          )
    }

    #expect(model.takeoffInputsOffscaleLow == false)
    #expect(model.takeoffInputsOffscaleHigh == true)
  }

  @Test
  func `G2+ takeoff weight below minimum sets takeoffInputsOffscaleLow flag`() throws {
    let conditions = Helper.createTestConditions(temperature: 15)
    let config = Helper.createTestConfiguration(weight: 4900)  // Below 5000 lbs minimum
    let runway = Helper.createTestRunway()
    let runwayInput = RunwayInput(from: runway, airport: runway.airport, notam: nil)

    let model = RegressionPerformanceModel(
      conditions: conditions,
      configuration: config,
      runway: runwayInput,
      notam: nil,
      aircraftType: .g1
    )

    switch model.takeoffRunFt {
      case .value, .valueWithUncertainty:
        break
      case .offscaleLow, .offscaleHigh, .notAvailable, .invalid, .notAuthorized:
        PerformanceCase(for: model, aircraftType: .g1)
          .fail(
            "Expected a computed value, got \(model.takeoffRunFt)",
            computing: "takeoff run"
          )
    }

    #expect(model.takeoffInputsOffscaleLow == true)
    #expect(model.takeoffInputsOffscaleHigh == false)
  }

  @Test
  func `G2+ takeoff weight above maximum sets takeoffInputsOffscaleHigh flag`() throws {
    let conditions = Helper.createTestConditions(temperature: 15)
    let config = Helper.createTestConfiguration(weight: 6050)  // Above 6000 lbs maximum
    let runway = Helper.createTestRunway()
    let runwayInput = RunwayInput(from: runway, airport: runway.airport, notam: nil)

    let model = RegressionPerformanceModel(
      conditions: conditions,
      configuration: config,
      runway: runwayInput,
      notam: nil,
      aircraftType: .g1
    )

    switch model.takeoffRunFt {
      case .value, .valueWithUncertainty:
        break
      case .offscaleLow, .offscaleHigh, .notAvailable, .invalid, .notAuthorized:
        PerformanceCase(for: model, aircraftType: .g1)
          .fail(
            "Expected a computed value, got \(model.takeoffRunFt)",
            computing: "takeoff run"
          )
    }

    #expect(model.takeoffInputsOffscaleLow == false)
    #expect(model.takeoffInputsOffscaleHigh == true)
  }

  // MARK: - Temperature Tests

  @Test
  func `G1 landing temperature below minimum sets landingInputsOffscaleLow flag`() throws {
    // Below 0°C minimum for flaps 100
    let conditions = Helper.createTestConditions(temperature: -5)
    let config = Helper.createTestConfiguration(weight: 5200, flapSetting: .flaps100)
    let runway = Helper.createTestRunway()
    let runwayInput = RunwayInput(from: runway, airport: runway.airport, notam: nil)

    let model = RegressionPerformanceModel(
      conditions: conditions,
      configuration: config,
      runway: runwayInput,
      notam: nil,
      aircraftType: .g1
    )

    switch model.landingRunFt {
      case .value, .valueWithUncertainty:
        break
      case .offscaleLow, .offscaleHigh, .notAvailable, .invalid, .notAuthorized:
        PerformanceCase(for: model, aircraftType: .g1)
          .fail(
            "Expected a computed value, got \(model.landingRunFt)",
            computing: "landing run"
          )
    }

    #expect(model.landingInputsOffscaleLow == true)
    #expect(model.landingInputsOffscaleHigh == false)
  }

  @Test
  func `G1 landing temperature above maximum sets landingInputsOffscaleHigh flag`() throws {
    // Above 50°C maximum for flaps 100
    let conditions = Helper.createTestConditions(temperature: 55)
    let config = Helper.createTestConfiguration(weight: 5200, flapSetting: .flaps100)
    let runway = Helper.createTestRunway()
    let runwayInput = RunwayInput(from: runway, airport: runway.airport, notam: nil)

    let model = RegressionPerformanceModel(
      conditions: conditions,
      configuration: config,
      runway: runwayInput,
      notam: nil,
      aircraftType: .g1
    )

    switch model.landingRunFt {
      case .value, .valueWithUncertainty:
        break
      case .offscaleLow, .offscaleHigh, .notAvailable, .invalid, .notAuthorized:
        PerformanceCase(for: model, aircraftType: .g1)
          .fail(
            "Expected a computed value, got \(model.landingRunFt)",
            computing: "landing run"
          )
    }

    #expect(model.landingInputsOffscaleLow == false)
    #expect(model.landingInputsOffscaleHigh == true)
  }

  @Test
  func `G1 takeoff temperature below minimum sets takeoffInputsOffscaleLow flag`() throws {
    let conditions = Helper.createTestConditions(temperature: -25)  // Below -20°C minimum
    let config = Helper.createTestConfiguration(weight: 5500)
    let runway = Helper.createTestRunway()
    let runwayInput = RunwayInput(from: runway, airport: runway.airport, notam: nil)

    let model = RegressionPerformanceModel(
      conditions: conditions,
      configuration: config,
      runway: runwayInput,
      notam: nil,
      aircraftType: .g1
    )

    switch model.takeoffRunFt {
      case .value, .valueWithUncertainty:
        break
      case .offscaleLow, .offscaleHigh, .notAvailable, .invalid, .notAuthorized:
        PerformanceCase(for: model, aircraftType: .g1)
          .fail(
            "Expected a computed value, got \(model.takeoffRunFt)",
            computing: "takeoff run"
          )
    }

    #expect(model.takeoffInputsOffscaleLow == true)
    #expect(model.takeoffInputsOffscaleHigh == false)
  }

  @Test
  func `G1 takeoff temperature above maximum sets takeoffInputsOffscaleHigh flag`() throws {
    let conditions = Helper.createTestConditions(temperature: 55)  // Above 50°C maximum
    let config = Helper.createTestConfiguration(weight: 5500)
    let runway = Helper.createTestRunway()
    let runwayInput = RunwayInput(from: runway, airport: runway.airport, notam: nil)

    let model = RegressionPerformanceModel(
      conditions: conditions,
      configuration: config,
      runway: runwayInput,
      notam: nil,
      aircraftType: .g1
    )

    switch model.takeoffRunFt {
      case .value, .valueWithUncertainty:
        break
      case .offscaleLow, .offscaleHigh, .notAvailable, .invalid, .notAuthorized:
        PerformanceCase(for: model, aircraftType: .g1)
          .fail(
            "Expected a computed value, got \(model.takeoffRunFt)",
            computing: "takeoff run"
          )
    }

    #expect(model.takeoffInputsOffscaleLow == false)
    #expect(model.takeoffInputsOffscaleHigh == true)
  }

  // MARK: - Altitude Tests

  @Test
  func `G1 landing altitude above maximum sets landingInputsOffscaleHigh flag`() throws {
    let conditions = Helper.createTestConditions(temperature: 15)
    let config = Helper.createTestConfiguration(weight: 5200)
    let runway = Helper.createTestRunway(elevation: 11000)  // Above 10000 ft maximum
    let runwayInput = RunwayInput(from: runway, airport: runway.airport, notam: nil)

    let model = RegressionPerformanceModel(
      conditions: conditions,
      configuration: config,
      runway: runwayInput,
      notam: nil,
      aircraftType: .g1
    )

    switch model.landingRunFt {
      case .value, .valueWithUncertainty:
        break
      case .offscaleLow, .offscaleHigh, .notAvailable, .invalid, .notAuthorized:
        PerformanceCase(for: model, aircraftType: .g1)
          .fail(
            "Expected a computed value, got \(model.landingRunFt)",
            computing: "landing run"
          )
    }

    #expect(model.landingInputsOffscaleLow == false)
    #expect(model.landingInputsOffscaleHigh == true)
  }

  @Test
  func `G1 takeoff altitude above maximum sets takeoffInputsOffscaleHigh flag`() throws {
    let conditions = Helper.createTestConditions(temperature: 15)
    let config = Helper.createTestConfiguration(weight: 5500)
    let runway = Helper.createTestRunway(elevation: 10500)  // Above 10000 ft maximum
    let runwayInput = RunwayInput(from: runway, airport: runway.airport, notam: nil)

    let model = RegressionPerformanceModel(
      conditions: conditions,
      configuration: config,
      runway: runwayInput,
      notam: nil,
      aircraftType: .g1
    )

    switch model.takeoffRunFt {
      case .value, .valueWithUncertainty:
        break
      case .offscaleLow, .offscaleHigh, .notAvailable, .invalid, .notAuthorized:
        PerformanceCase(for: model, aircraftType: .g1)
          .fail(
            "Expected a computed value, got \(model.takeoffRunFt)",
            computing: "takeoff run"
          )
    }

    #expect(model.takeoffInputsOffscaleLow == false)
    #expect(model.takeoffInputsOffscaleHigh == true)
  }

  // MARK: - Within Bounds Tests

  @Test
  func `G1 landing within bounds returns valid values and no offscale flags`() throws {
    let conditions = Helper.createTestConditions(temperature: 15)
    let config = Helper.createTestConfiguration(weight: 5200)  // Within 4500-5550 lbs
    let runway = Helper.createTestRunway(elevation: 5000)  // Within 0-10000 ft
    let runwayInput = RunwayInput(from: runway, airport: runway.airport, notam: nil)

    let model = RegressionPerformanceModel(
      conditions: conditions,
      configuration: config,
      runway: runwayInput,
      notam: nil,
      aircraftType: .g1
    )

    // Should return actual values, not offscale
    switch model.landingRunFt {
      case .value, .valueWithUncertainty:
        break  // Expected
      case .offscaleLow, .offscaleHigh, .notAvailable, .invalid, .notAuthorized:
        PerformanceCase(for: model, aircraftType: .g1)
          .fail(
            "Expected a computed value, got \(model.landingRunFt)",
            computing: "landing run"
          )
    }

    switch model.landingDistanceFt {
      case .value, .valueWithUncertainty:
        break  // Expected
      case .offscaleLow, .offscaleHigh, .notAvailable, .invalid, .notAuthorized:
        PerformanceCase(for: model, aircraftType: .g1)
          .fail(
            "Expected a computed value, got \(model.landingDistanceFt)",
            computing: "landing distance"
          )
    }

    // Flags should not be set
    #expect(model.landingInputsOffscaleLow == false)
    #expect(model.landingInputsOffscaleHigh == false)
  }

  @Test
  func `G1 takeoff within bounds returns valid values and no offscale flags`() throws {
    let conditions = Helper.createTestConditions(temperature: 25)
    let config = Helper.createTestConfiguration(weight: 5500)  // Within 5000-6000 lbs
    let runway = Helper.createTestRunway(elevation: 3000)  // Within 0-10000 ft
    let runwayInput = RunwayInput(from: runway, airport: runway.airport, notam: nil)

    let model = RegressionPerformanceModel(
      conditions: conditions,
      configuration: config,
      runway: runwayInput,
      notam: nil,
      aircraftType: .g1
    )

    // Should return actual values, not offscale
    switch model.takeoffRunFt {
      case .value, .valueWithUncertainty:
        break  // Expected
      case .offscaleLow, .offscaleHigh, .notAvailable, .invalid, .notAuthorized:
        PerformanceCase(for: model, aircraftType: .g1)
          .fail(
            "Expected a computed value, got \(model.takeoffRunFt)",
            computing: "takeoff run"
          )
    }

    switch model.takeoffDistanceFt {
      case .value, .valueWithUncertainty:
        break  // Expected
      case .offscaleLow, .offscaleHigh, .notAvailable, .invalid, .notAuthorized:
        PerformanceCase(for: model, aircraftType: .g1)
          .fail(
            "Expected a computed value, got \(model.takeoffDistanceFt)",
            computing: "takeoff distance"
          )
    }

    // Flags should not be set
    #expect(model.takeoffInputsOffscaleLow == false)
    #expect(model.takeoffInputsOffscaleHigh == false)
  }

  // MARK: - Flap Setting Specific Tests

  @Test
  func `G1 landing flaps 50 ice temperature bounds are different`() throws {
    // Flaps 50 ice has temperature range -20°C to 10°C (different from flaps 100)
    // Above 10°C max for flaps 50 ice
    let conditions = Helper.createTestConditions(temperature: 15)
    let config = Helper.createTestConfiguration(weight: 5200, flapSetting: .flaps50Ice)
    let runway = Helper.createTestRunway()
    let runwayInput = RunwayInput(from: runway, airport: runway.airport, notam: nil)

    let model = RegressionPerformanceModel(
      conditions: conditions,
      configuration: config,
      runway: runwayInput,
      notam: nil,
      aircraftType: .g1
    )

    switch model.landingRunFt {
      case .value, .valueWithUncertainty:
        break
      case .offscaleLow, .offscaleHigh, .notAvailable, .invalid, .notAuthorized:
        PerformanceCase(for: model, aircraftType: .g1)
          .fail(
            "Expected a computed value, got \(model.landingRunFt)",
            computing: "landing run"
          )
    }

    #expect(model.landingInputsOffscaleLow == false)
    #expect(model.landingInputsOffscaleHigh == true)
  }

  @Test
  func `G1 landing flaps 50 ice within temperature bounds returns valid values and no flags`()
    throws
  {
    let conditions = Helper.createTestConditions(temperature: 5)  // Within -20°C to 10°C
    let config = Helper.createTestConfiguration(weight: 5200, flapSetting: .flaps50Ice)
    let runway = Helper.createTestRunway()
    let runwayInput = RunwayInput(from: runway, airport: runway.airport, notam: nil)

    let model = RegressionPerformanceModel(
      conditions: conditions,
      configuration: config,
      runway: runwayInput,
      notam: nil,
      aircraftType: .g1
    )

    switch model.landingRunFt {
      case .value, .valueWithUncertainty:
        break  // Expected
      case .offscaleLow, .offscaleHigh, .notAvailable, .invalid, .notAuthorized:
        PerformanceCase(for: model, aircraftType: .g1)
          .fail(
            "Expected a computed value, got \(model.landingRunFt)",
            computing: "landing run"
          )
    }

    #expect(model.landingInputsOffscaleLow == false)
    #expect(model.landingInputsOffscaleHigh == false)
  }

  // MARK: - En Route Climb

  /// The fitted en route climb equations turn past the conditions they were made from: the
  /// ice-contaminated schedule is tabulated only to +10 °C, and at the temperatures the Climb tab
  /// can ask for the polynomial reports a descent. A figure like that is not an estimate, so the
  /// model reports nothing rather than printing it.
  @Test
  func `en route climb past the ice-contaminated envelope is not available`() {
    let model = Self.model(temperature: 50, iceProtection: true)

    #expect(model.enrouteClimbGradientFtNM == .notAvailable)
    #expect(model.enrouteClimbRateFtMin == .notAvailable)
    #expect(model.enrouteClimbSpeedKIAS == .notAvailable)
  }

  @Test
  func `en route climb inside the envelope still extrapolates a figure`() throws {
    let model = Self.model(temperature: 5, iceProtection: true)

    let gradient = try #require(model.enrouteClimbGradientFtNM.nominal)
    let rate = try #require(model.enrouteClimbRateFtMin.nominal)
    #expect(gradient > 0)
    #expect(rate > 0)
  }
}
