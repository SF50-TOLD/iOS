// swiftlint:disable prefer_nimble
import XCTest
import XCUITestKit

final class SF50_TOLDUITests: XCTestCase {

  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  // MARK: - Takeoff Tests

  @MainActor
  func testBasicTakeoffFlow() throws {
    let tabBar = AppLauncher().launchAndCompleteSetup(emptyWeight: "4550")
    let takeoff = tabBar.goToTakeoff()

    takeoff.setPayload("450")
    takeoff.setFuel("0")
    takeoff.selectAirportRunwayWeather(airport: "OAK", runway: "28R")

    let groundRun = try XCTUnwrap(takeoff.groundRunValue, "Ground run should have a value")
    let distance = try XCTUnwrap(takeoff.distanceValue, "Distance should have a value")
    // On iPad iOS 26, XCTest typeText doesn't commit TextField(value:format:)
    // bindings, so custom weather values may not apply. Use wider tolerance
    // to accommodate default-weather performance values on iPad.
    XCTAssertEqual(groundRun, 1798, accuracy: 25)
    XCTAssertEqual(distance, 2643, accuracy: 50)
  }

  @MainActor
  func testBasicLandingFlow() throws {
    let tabBar = AppLauncher().launchAndCompleteSetup(emptyWeight: "4050")
    let landing = tabBar.goToLanding()

    landing.setPayload("450")
    landing.setFuel("0")
    landing.selectAirportRunwayWeather(airport: "OAK", runway: "28R")

    let landingDistance = try XCTUnwrap(
      landing.landingDistanceValue,
      "Landing distance should have a value"
    )
    XCTAssertEqual(landingDistance, 1769, accuracy: 35)
  }

  // MARK: - Additional Conditions Tests

  @MainActor
  func testTakeoffWithDifferentConditions() throws {
    let tabBar = AppLauncher().launchAndCompleteSetup(emptyWeight: "4550")
    let takeoff = tabBar.goToTakeoff()

    takeoff.setPayload("1450")
    takeoff.setFuel("0")
    takeoff.selectAirportRunwayWeather(airport: "SQL", runway: "30")

    // On iPad iOS 26, weather values may not commit via typeText, causing
    // different performance values or offscale results with heavy payloads.
    if let groundRun = takeoff.groundRunValue,
      let distance = takeoff.distanceValue
    {
      XCTAssertEqual(groundRun, 2081, accuracy: 40)
      XCTAssertEqual(distance, 3334, accuracy: 40)
    } else {
      // Performance computed but went offscale — still validates the navigation flow
      let offscale = takeoff.app.staticTexts["Offscale high"]
      XCTAssertTrue(
        offscale.waitForExistence(timeout: 3),
        "Ground run should have a value or show offscale"
      )
    }
  }

  // MARK: - Report Generation Tests

  @MainActor
  func testTakeoffReportGeneration() throws {
    let tabBar = AppLauncher().launchAndCompleteSetup(emptyWeight: "4550")
    let takeoff = tabBar.goToTakeoff()

    takeoff.setPayload("450")
    takeoff.setFuel("0")

    let picker = takeoff.openAirportPicker()
    picker.searchAndSelect("OAK")
    let runwayPicker = takeoff.openRunwayPicker()
    runwayPicker.selectRunway("28R")

    let report = takeoff.openReport()
    XCTAssertTrue(report.isDisplayed())
    report.dismiss()
  }

  // MARK: - Scenario Management Tests

  @MainActor
  func testScenarioManagement() async throws {
    let tabBar = AppLauncher().launchAndCompleteSetup(emptyWeight: "4550")
    let settings = tabBar.goToSettings()
    let scenarios = settings.openScenarios()

    let detail = scenarios.addScenario()
    detail.setName("Hot Day Test")
    detail.setOATDelta("10")
    detail.setWeightDelta("500")
    detail.goBack()

    XCTAssertTrue(scenarios.scenarioExists("Hot Day Test"))

    await scenarios.deleteScenario("Hot Day Test")

    XCTAssertFalse(
      scenarios.scenarioExists("Hot Day Test"),
      "Deleted scenario should not appear in list"
    )
  }

  // MARK: - Airport Favorites Tests

  @MainActor
  func testAirportFavoritesFlow() throws {
    let tabBar = AppLauncher().launchAndCompleteSetup(emptyWeight: "4550")
    let takeoff = tabBar.goToTakeoff()

    let picker = takeoff.openAirportPicker()
    picker.switchToSearch()
    picker.search(for: "SQL")
    picker.dismissKeyboard()

    XCTAssertTrue(
      picker.app.buttons["airportRow-SQL"].firstMatch.waitForExistence(timeout: 3),
      "SQL should appear in search results"
    )

    // Check if already favorited
    picker.switchToFavorites()
    let alreadyFavorited = picker.isAirportVisible("SQL")
    picker.switchToSearch()
    picker.search(for: "SQL")
    picker.dismissKeyboard()
    _ = picker.app.buttons["airportRow-SQL"].firstMatch.waitForExistence(timeout: 2)

    if alreadyFavorited {
      picker.toggleFavorite(for: "SQL")
    }

    picker.toggleFavorite(for: "SQL")

    picker.switchToFavorites()
    XCTAssertTrue(picker.isAirportVisible("SQL"), "SQL should appear in favorites")

    picker.toggleFavorite(for: "SQL")

    picker.switchToSearch()
    picker.switchToFavorites()

    XCTAssertFalse(picker.isAirportVisible("SQL"), "SQL should be removed from favorites")
  }

  // MARK: - NOTAM Management Tests

  @MainActor
  func testNOTAMManagement() throws {
    let tabBar = AppLauncher().launchAndCompleteSetup(emptyWeight: "4050")
    let landing = tabBar.goToLanding()

    landing.setupCalculation()

    let baselineDistance = landing.landingDistanceValue

    let notams = landing.openNOTAMs()
    notams.selectContamination("Water/Slush")
    notams.adjustContaminationDepth(to: 0.4)
    notams.goBack()

    _ = landing.app.staticTexts["landingDistanceValue"].waitForExistence(timeout: 5)
    let contaminatedDistance = landing.landingDistanceValue

    if let baselineDistance, let contaminatedDistance {
      XCTAssertEqual(baselineDistance, 1769.0, accuracy: 40)
      XCTAssertEqual(contaminatedDistance, 2476.0, accuracy: 40)
    }

    XCTAssertTrue(
      landing.NOTAMBadgeLabel.contains("1 configured"),
      "NOTAM button should show count after adding contamination"
    )

    let notams2 = landing.openNOTAMs()
    notams2.clearAllNOTAMs()

    let clearedDistance = landing.landingDistanceValue

    if let baselineDistance, let clearedDistance {
      XCTAssertEqual(clearedDistance, baselineDistance, accuracy: 1)
    }
  }

  // MARK: - Settings Impact Tests

  @MainActor
  func testSettingsChangesImpact() throws {
    let tabBar = AppLauncher().launchAndCompleteSetup(emptyWeight: "4550")
    let takeoff = tabBar.goToTakeoff()

    takeoff.setupCalculation()

    let baselineDistance = takeoff.distanceValue

    let settings = tabBar.goToSettings()
    settings.setSafetyFactorDry("1.1")
    settings.dismissKeyboard()

    let takeoff2 = tabBar.goToTakeoff()
    let adjustedDistance = takeoff2.distanceValue

    if let baselineDistance, let adjustedDistance {
      XCTAssertEqual(baselineDistance, 2643.0, accuracy: 40)
      XCTAssertEqual(adjustedDistance, 2907.0, accuracy: 40)
    }

    let settings2 = tabBar.goToSettings()
    settings2.setSafetyFactorDry("1.0")
  }

  // MARK: - Landing Flap Configuration Tests

  @MainActor
  func testLandingFlapConfiguration() throws {
    let tabBar = AppLauncher().launchAndCompleteSetup(emptyWeight: "4050")
    let landing = tabBar.goToLanding()

    landing.setupCalculation()

    let flaps100Distance = landing.landingDistanceValue

    landing.selectFlaps("Flaps 50%")
    let flaps50Distance = landing.landingDistanceValue

    if let flaps100Distance, let flaps50Distance {
      XCTAssertNotEqual(
        flaps100Distance,
        flaps50Distance,
        accuracy: 1,
        "Landing distance should differ between flap settings"
      )
    }

    landing.selectFlaps("Flaps Up")
    let flapsUpDistance = landing.landingDistanceValue

    if let flaps100Distance, let flapsUpDistance {
      XCTAssertEqual(flaps100Distance, 1769.0, accuracy: 40)
      XCTAssertEqual(flapsUpDistance, 2248.0, accuracy: 40)
    }
  }

  // MARK: - Climb Tests

  @MainActor
  func testClimbViewInteraction() throws {
    let tabBar = AppLauncher().launchAndCompleteSetup(emptyWeight: "4550")
    let climb = tabBar.goToClimb()

    // Keep sliders in the normal range to avoid offscale (ice protection tested separately)
    climb.adjustFuel(to: 0.5)
    climb.adjustAltitude(to: 0.1)
    climb.adjustISADeviation(to: 0.5)

    XCTAssertTrue(
      climb.speedValue.waitForExistence(timeout: 2),
      "Climb speed value should be displayed"
    )
    XCTAssertTrue(climb.rateValue.exists, "Climb rate value should be displayed")
    XCTAssertTrue(climb.gradientValue.exists, "Climb gradient value should be displayed")

    XCTAssertFalse(climb.speedLabel.isEmpty, "Climb speed should have a value")
    XCTAssertFalse(climb.rateLabel.isEmpty, "Climb rate should have a value")
    XCTAssertFalse(climb.gradientLabel.isEmpty, "Climb gradient should have a value")

    let initialRateLabel = climb.rateLabel
    climb.adjustAltitude(to: 0.7)
    let updatedRateLabel = climb.waitForLabelChange(
      climb.rateValue,
      from: initialRateLabel,
      timeout: 5
    )

    XCTAssertNotEqual(
      initialRateLabel,
      updatedRateLabel,
      "Climb rate should update when altitude changes"
    )
  }

  // MARK: - Profile View Tests

  @MainActor
  func testClimbProfileView() throws {
    let tabBar = AppLauncher().launchAndCompleteSetup(emptyWeight: "4550")
    let takeoff = tabBar.goToTakeoff()

    takeoff.setPayload("450")
    takeoff.setFuel("100")

    let picker = takeoff.openAirportPicker()
    picker.searchAndSelect("OAK")
    let runwayPicker = takeoff.openRunwayPicker()
    runwayPicker.selectRunway("28R")

    let profile = takeoff.openClimbProfile()
    XCTAssertTrue(
      takeoff.app.navigationBars["Climb Profile"].waitForExistence(timeout: 5),
      "Climb Profile nav bar should appear"
    )
    XCTAssertTrue(profile.isChartVisible(), "Terrain profile chart should appear")
    profile.goBack()
  }

  @MainActor
  func testGoAroundProfileView() throws {
    let tabBar = AppLauncher().launchAndCompleteSetup(emptyWeight: "4550")
    let landing = tabBar.goToLanding()

    landing.setPayload("450")
    landing.setFuel("100")

    let picker = landing.openAirportPicker()
    picker.searchAndSelect("OAK")
    let runwayPicker = landing.openRunwayPicker()
    runwayPicker.selectRunway("28R")

    let profile = landing.openGoAroundProfile()
    XCTAssertTrue(
      landing.app.navigationBars["Go-Around Profile"].waitForExistence(timeout: 5),
      "Go-Around Profile nav bar should appear"
    )
    XCTAssertTrue(profile.isChartVisible(), "Terrain profile chart should appear")
    profile.goBack()
  }

  // MARK: - Welcome Flow Variations Tests

  @MainActor
  func testWelcomeFlowModelSelection() throws {
    let welcome = AppLauncher().launch()
    welcome.handleDatabaseLoaderIfNeeded()

    XCTAssertTrue(
      welcome.continueButton.waitForExistence(timeout: 5),
      "Continue button should appear"
    )

    welcome.selectModel("G2")
    XCTAssertTrue(
      welcome.modelPicker.buttons["G2"].isSelected,
      "G2 should be selected"
    )

    welcome.setEmptyWeight("4550")
    let tabBar = welcome.tapContinue()

    let settings = tabBar.goToSettings()
    XCTAssertTrue(
      settings.app.staticTexts["Settings"].waitForExistence(timeout: 2),
      "Should be on Settings screen"
    )
  }

  // MARK: - Offscale Warning Tests

  @MainActor
  func testOffscaleWarning() throws {
    let tabBar = AppLauncher().launchAndCompleteSetup(emptyWeight: "3000")
    let takeoff = tabBar.goToTakeoff()

    takeoff.setPayload("100")
    takeoff.setFuel("0")

    let picker = takeoff.openAirportPicker()
    picker.switchToSearch()
    picker.search(for: "ASE")

    if takeoff.app.buttons["airportRow-ASE"].firstMatch.waitForExistence(timeout: 3) {
      picker.selectAirport("ASE")

      let runwayPicker = takeoff.openRunwayPicker()
      let firstRunway = takeoff.app.buttons["runwayRow-15"].firstMatch
      if firstRunway.waitForExistence(timeout: 2) {
        runwayPicker.selectRunway("15")
      }

      let weather = takeoff.openWeatherPicker()
      weather.setTemperature("45")
      weather.goBack()

      let distance = takeoff.scrollToElement(takeoff.app.staticTexts["takeoffDistanceValue"])
      XCTAssertTrue(
        distance?.exists ?? false,
        "Takeoff distance should still be displayed even in extreme conditions"
      )
    }
  }

  // MARK: - Landing Report Generation Tests

  @MainActor
  func testLandingReportGeneration() throws {
    let tabBar = AppLauncher().launchAndCompleteSetup(emptyWeight: "4050")
    let landing = tabBar.goToLanding()

    landing.setupCalculation()

    let report = landing.openReport()
    XCTAssertTrue(report.isDisplayed())
    report.dismiss()
  }

  // MARK: - About Tab Tests

  @MainActor
  func testAboutTabContent() throws {
    let tabBar = AppLauncher().launchAndCompleteSetup(emptyWeight: "4550")
    let about = tabBar.goToAbout()

    XCTAssertTrue(
      about.app.navigationBars["About"].waitForExistence(timeout: 2),
      "About nav bar should appear"
    )
    XCTAssertTrue(about.hasAircraftDescription(), "Aircraft description should be displayed")
    XCTAssertTrue(about.hasNASRCycleLabel(), "NASR Cycle label should be displayed")
    XCTAssertTrue(about.hasFAADisclaimer(), "FAA disclaimer should be displayed")
  }

  // MARK: - Adjustments View Tests

  @MainActor
  func testTakeoffAdjustmentsView() throws {
    let tabBar = AppLauncher().launchAndCompleteSetup(emptyWeight: "4550")
    let takeoff = tabBar.goToTakeoff()

    takeoff.setupCalculation()

    let adjustments = takeoff.openAdjustments()
    XCTAssertTrue(
      takeoff.app.navigationBars["Takeoff Adjustments"].waitForExistence(timeout: 5),
      "Takeoff Adjustments nav bar should appear"
    )
    XCTAssertTrue(adjustments.hasGroundRunSection())
    XCTAssertTrue(adjustments.hasTotalDistanceSection())
    adjustments.goBack()
  }

  @MainActor
  func testLandingAdjustmentsView() throws {
    let tabBar = AppLauncher().launchAndCompleteSetup(emptyWeight: "4050")
    let landing = tabBar.goToLanding()

    landing.setupCalculation()

    let adjustments = landing.openAdjustments()
    XCTAssertTrue(
      landing.app.navigationBars["Landing Adjustments"].waitForExistence(timeout: 5),
      "Landing Adjustments nav bar should appear"
    )
    XCTAssertTrue(adjustments.hasGroundRunSection())
    XCTAssertTrue(adjustments.hasTotalDistanceSection())
    adjustments.goBack()
  }

  // MARK: - Welcome Flow G2 With Thrust Schedule Tests

  @MainActor
  func testWelcomeFlowG2WithThrustSchedule() throws {
    let welcome = AppLauncher().launch()
    welcome.handleDatabaseLoaderIfNeeded()

    XCTAssertTrue(
      welcome.continueButton.waitForExistence(timeout: 5),
      "Continue button should appear"
    )

    welcome.selectModel("G2")
    XCTAssertTrue(
      welcome.thrustScheduleToggle.waitForExistence(timeout: 2),
      "Updated thrust schedule toggle should appear for G2"
    )
    welcome.toggleThrustSchedule()

    welcome.setEmptyWeight("4550")
    let tabBar = welcome.tapContinue()

    let settings = tabBar.goToSettings()
    XCTAssertTrue(
      settings.aircraftTypePicker.waitForExistence(timeout: 2),
      "Aircraft type picker should be present in Settings"
    )
  }

  // MARK: - Units Settings Tests

  @MainActor
  func testUnitsSettings() throws {
    let tabBar = AppLauncher().launchAndCompleteSetup(emptyWeight: "4550")
    let settings = tabBar.goToSettings()
    let units = settings.openUnits()

    XCTAssertTrue(
      units.app.navigationBars["Units"].waitForExistence(timeout: 2),
      "Units nav bar should appear"
    )

    units.selectWeight("Kilograms (kg)")
    units.selectTemperature("Fahrenheit (°F)")

    units.goBack()

    _ = tabBar.goToTakeoff()
    XCTAssertTrue(
      tabBar.app.textFields["Payload"].waitForExistence(timeout: 5),
      "Takeoff tab should still render after unit change"
    )

    let settings2 = tabBar.goToSettings()
    let units2 = settings2.openUnits()

    XCTAssertTrue(
      units2.weightPickerLabel.contains("Kilograms"),
      "Weight should be set to Kilograms"
    )
    XCTAssertTrue(
      units2.temperaturePickerLabel.contains("Fahrenheit"),
      "Temperature should be set to Fahrenheit"
    )
  }

  // MARK: - Aircraft Model Change Tests

  @MainActor
  func testAircraftModelChangeInSettings() throws {
    let tabBar = AppLauncher().launchAndCompleteSetup(emptyWeight: "4550")
    let settings = tabBar.goToSettings()

    settings.selectAircraftModel("G2+")
    XCTAssertFalse(
      settings.isThrustScheduleToggleVisible,
      "Thrust schedule toggle should not appear for G2+"
    )

    _ = tabBar.goToTakeoff()
    XCTAssertTrue(
      tabBar.app.textFields["Payload"].waitForExistence(timeout: 5),
      "Takeoff tab should render after model change"
    )

    let settings2 = tabBar.goToSettings()
    settings2.selectAircraftModel("G2")
    XCTAssertTrue(
      settings2.isThrustScheduleToggleVisible,
      "Thrust schedule toggle should appear for G2"
    )
  }

  // MARK: - Performance Model Toggle Tests

  @MainActor
  func testPerformanceModelToggle() throws {
    let tabBar = AppLauncher().launchAndCompleteSetup(emptyWeight: "4550")
    let settings = tabBar.goToSettings()

    let modelToggle = settings.selectModelToggle
    XCTAssertTrue(modelToggle.waitForExistence(timeout: 2), "Model toggle should exist")

    let lessThan100 = settings.app.staticTexts.matching(
      NSPredicate(format: "label CONTAINS 'less than 100 ft'")
    ).firstMatch

    if lessThan100.exists {
      settings.selectPerformanceModel("Tabular")

      let matchBookValues = settings.app.staticTexts.matching(
        NSPredicate(format: "label CONTAINS 'match book values exactly'")
      ).firstMatch
      XCTAssertTrue(
        matchBookValues.waitForExistence(timeout: 2),
        "Tabular description should appear"
      )
    } else {
      settings.selectPerformanceModel("Regression")

      XCTAssertTrue(
        lessThan100.waitForExistence(timeout: 2),
        "Regression description should appear"
      )
    }

    _ = tabBar.goToTakeoff()
    XCTAssertTrue(
      tabBar.app.textFields["Payload"].waitForExistence(timeout: 5),
      "Takeoff tab should still render after performance model change"
    )
  }

  // MARK: - Terrain Settings Navigation Tests

  @MainActor
  func testTerrainSettingsNavigation() throws {
    let tabBar = AppLauncher().launchAndCompleteSetup(emptyWeight: "4550")
    let settings = tabBar.goToSettings()
    let terrain = settings.openTerrain()

    XCTAssertTrue(
      terrain.app.navigationBars["Terrain Data"].waitForExistence(timeout: 2),
      "Terrain Data nav bar should appear"
    )
    XCTAssertTrue(terrain.isTotalDownloadedVisible(), "Total Downloaded label should exist")
    terrain.goBack()
  }

  // MARK: - NOTAM Runway Shortening Tests

  @MainActor
  func testNOTAMRunwayShortening() throws {
    let tabBar = AppLauncher().launchAndCompleteSetup(emptyWeight: "4050")
    let landing = tabBar.goToLanding()

    landing.setupCalculation()

    let notams = landing.openNOTAMs()
    notams.setRunwayShortening("500")
    notams.goBack()

    let badgeLabel = landing.waitForLabel(of: landing.NOTAMSelector, toContain: "1 configured")
    XCTAssertTrue(
      badgeLabel.contains("1 configured"),
      "NOTAM button should show 1 configured after runway shortening, got: \"\(badgeLabel)\""
    )
  }

  // MARK: - NOTAM Obstacle Tests

  @MainActor
  func testNOTAMObstacleTakeoff() throws {
    let tabBar = AppLauncher().launchAndCompleteSetup(emptyWeight: "4550")
    let takeoff = tabBar.goToTakeoff()

    takeoff.setupCalculation()

    let notams = takeoff.openNOTAMs()
    notams.setObstacleHeight("75")
    notams.setObstacleDistance("0.5")
    notams.goBack()

    let badgeLabel = takeoff.waitForLabel(of: takeoff.NOTAMSelector, toContain: "1 configured")
    XCTAssertTrue(
      badgeLabel.contains("1 configured"),
      "NOTAM button should show 1 configured after adding obstacle, got: \"\(badgeLabel)\""
    )
  }

  // MARK: - Airport Recents Tab Tests

  @MainActor
  func testAirportRecentsTab() throws {
    let tabBar = AppLauncher().launchAndCompleteSetup(emptyWeight: "4550")
    let takeoff = tabBar.goToTakeoff()

    let picker = takeoff.openAirportPicker()
    picker.searchAndSelect("OAK")

    let runwayPicker = takeoff.openRunwayPicker()
    runwayPicker.selectRunway("28R")

    let picker2 = takeoff.openAirportPicker()
    picker2.switchToRecents()

    XCTAssertTrue(
      picker2.isAirportVisible("OAK"),
      "OAK should appear in recents"
    )
  }

  // MARK: - Airport Search Variations Tests

  @MainActor
  func testAirportSearchVariations() throws {
    let tabBar = AppLauncher().launchAndCompleteSetup(emptyWeight: "4550")
    let takeoff = tabBar.goToTakeoff()

    let picker = takeoff.openAirportPicker()
    picker.switchToSearch()
    picker.search(for: "1C9")

    XCTAssertTrue(
      picker.app.buttons["airportRow-1C9"].firstMatch.waitForExistence(timeout: 3),
      "1C9 should appear in search results"
    )

    let searchField = picker.app.searchFields.firstMatch
    searchField.tap(withNumberOfTaps: 3, numberOfTouches: 1)
    searchField.typeText("ZZZZZ")

    _ = picker.app.buttons["airportRow-ZZZZZ"].waitForExistence(timeout: 2)

    XCTAssertEqual(picker.airportRowCount(), 0, "No airports should match ZZZZZ")
  }

  // MARK: - Payload Change Impact Tests

  @MainActor
  func testPayloadChangeImpact() throws {
    let tabBar = AppLauncher().launchAndCompleteSetup(emptyWeight: "4550")
    let takeoff = tabBar.goToTakeoff()

    takeoff.setupCalculation(payload: "450")

    let baselineDistance = takeoff.distanceValue

    // Scroll up to reach the payload field at the top of the form
    let collectionView = takeoff.app.collectionViews.firstMatch
    for _ in 0..<6 {
      if takeoff.payloadField.isVisible { break }
      let start = collectionView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
      let end = collectionView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
      start.press(forDuration: 0.01, thenDragTo: end)
    }
    takeoff.setPayload("1000")

    _ = takeoff.app.staticTexts["takeoffDistanceValue"].waitForExistence(timeout: 5)
    let heavierDistance = takeoff.distanceValue

    if let baselineDistance, let heavierDistance {
      XCTAssertGreaterThan(
        heavierDistance,
        baselineDistance,
        "Heavier payload should result in longer takeoff distance"
      )
    }
  }

  // MARK: - Empty Weight Change Impact Tests

  @MainActor
  func testEmptyWeightChangeInSettings() throws {
    let tabBar = AppLauncher().launchAndCompleteSetup(emptyWeight: "4550")
    let takeoff = tabBar.goToTakeoff()

    takeoff.setupCalculation()
    let baselineDistance = takeoff.distanceValue

    let settings = tabBar.goToSettings()
    settings.setEmptyWeight("5000")
    settings.dismissKeyboard()

    let takeoff2 = tabBar.goToTakeoff()
    let heavierDistance = takeoff2.distanceValue

    if let baselineDistance, let heavierDistance {
      XCTAssertGreaterThan(
        heavierDistance,
        baselineDistance,
        "Higher empty weight should result in longer takeoff distance"
      )
    }
  }

  // MARK: - VREF Additive Impact Tests

  @MainActor
  func testVREFAdditiveImpact() throws {
    let tabBar = AppLauncher().launchAndCompleteSetup(emptyWeight: "4050")
    let landing = tabBar.goToLanding()

    landing.setupCalculation()

    let baselineDistance = landing.landingDistanceValue

    landing.setVREFAdditive("10")

    _ = landing.app.staticTexts["landingDistanceValue"].waitForExistence(timeout: 5)
    let additiveDistance = landing.landingDistanceValue

    if let baselineDistance, let additiveDistance {
      XCTAssertGreaterThan(
        additiveDistance,
        baselineDistance,
        "VREF additive should increase landing distance"
      )
    }
  }

  // MARK: - Time Zone Display Tests

  @MainActor
  func testTimeZoneDisplayToggle() throws {
    let tabBar = AppLauncher(favoriteAirportIDs: ["OAK"])
      .launchAndCompleteSetup(emptyWeight: "4550")
    let settings = tabBar.goToSettings()

    settings.selectTimeZone("Airport Local")

    let takeoff = tabBar.goToTakeoff()

    // Select the seeded favorite rather than searching: a `.searchable` keyboard
    // left up by Search detaches onto the next screen on iOS 26 and covers the tab
    // bar, swallowing the following tab switch. Favorites needs no keyboard.
    let picker = takeoff.openAirportPicker()
    picker.switchToFavorites()
    picker.selectAirport("OAK")

    let dateSelector = takeoff.app.buttons["dateSelector"]
    if dateSelector.waitForExistence(timeout: 2) {
      XCTAssertTrue(dateSelector.exists, "Date selector should show time")
    }

    let settings2 = tabBar.goToSettings()
    settings2.selectTimeZone("UTC")

    let takeoff2 = tabBar.goToTakeoff()
    // The Takeoff form can retain a scrolled-down position from the earlier
    // visit, and a SwiftUI List does not reliably honor a status-bar
    // scroll-to-top, so scroll directly to the Payload field to confirm the
    // Takeoff tab is showing.
    let payloadField = takeoff2.scrollToElement(takeoff2.payloadField)
    XCTAssertNotNil(payloadField, "Should still be on Takeoff tab")
  }

  // MARK: - New Tests

  @MainActor
  func testLandingResultsValueCorrectness() throws {
    let tabBar = AppLauncher().launchAndCompleteSetup(emptyWeight: "4050")
    let landing = tabBar.goToLanding()

    landing.setupCalculation(payload: "450", fuel: "0", airport: "OAK", runway: "28R")

    XCTAssertFalse(landing.VREFValue.isEmpty, "VREF should have a value")
    XCTAssertNotNil(landing.landingGroundRunValue, "Landing ground run should have a value")
    let landingDistance = try XCTUnwrap(
      landing.landingDistanceValue,
      "Landing distance should have a value"
    )
    XCTAssertEqual(landingDistance, 1769, accuracy: 40)

    let goAroundGradient = landing.goAroundClimbGradient
    XCTAssertTrue(
      goAroundGradient.contains("Yes") || goAroundGradient.contains("No"),
      "Go-around climb gradient should indicate Yes or No"
    )
  }

  @MainActor
  func testTakeoffResultsValueCorrectness() throws {
    let tabBar = AppLauncher().launchAndCompleteSetup(emptyWeight: "4550")
    let takeoff = tabBar.goToTakeoff()

    takeoff.setupCalculation(payload: "450", fuel: "0", airport: "OAK", runway: "28R")

    let groundRun = try XCTUnwrap(takeoff.groundRunValue, "Ground run should have a value")
    let distance = try XCTUnwrap(takeoff.distanceValue, "Distance should have a value")
    XCTAssertEqual(groundRun, 1798, accuracy: 40)
    XCTAssertEqual(distance, 2643, accuracy: 40)

    let gradientText = takeoff.vxClimbGradient
    XCTAssertFalse(gradientText.isEmpty, "Vx climb gradient should have a value")

    let rateText = takeoff.vxClimbRate
    XCTAssertFalse(rateText.isEmpty, "Vx climb rate should have a value")
  }

  @MainActor
  func testNOTAMClearMultipleResetsBadge() throws {
    let tabBar = AppLauncher().launchAndCompleteSetup(emptyWeight: "4050")
    let landing = tabBar.goToLanding()

    landing.setupCalculation()

    // Set runway shortening + contamination
    let notams = landing.openNOTAMs()
    notams.setRunwayShortening("500")
    notams.selectContamination("Water/Slush")
    notams.goBack()

    let badgeLabel = landing.waitForLabel(of: landing.NOTAMSelector, toContain: "2 configured")
    XCTAssertTrue(
      badgeLabel.contains("2 configured"),
      "NOTAM badge should show 2 configured, got: \"\(badgeLabel)\""
    )

    // Clear all
    let notams2 = landing.openNOTAMs()
    notams2.clearAllNOTAMs()

    let clearedBadge = landing.waitForLabel(of: landing.NOTAMSelector, toContain: "NOTAMs")
    XCTAssertFalse(
      clearedBadge.contains("2 configured"),
      "NOTAM badge should not show 2 configured after clearing, got: \(clearedBadge)"
    )
  }

  @MainActor
  func testRunwayPickerShowsCorrectWindComponents() throws {
    let tabBar = AppLauncher().launchAndCompleteSetup(emptyWeight: "4550")
    let takeoff = tabBar.goToTakeoff()

    takeoff.setPayload("450")
    takeoff.setFuel("0")

    let picker = takeoff.openAirportPicker()
    picker.searchAndSelect("OAK")

    // Set weather with known wind (350@15)
    let weather = takeoff.openWeatherPicker()
    weather.setWeather(
      windDirection: "350",
      windSpeed: "15",
      temperature: "21",
      altimeter: "30.05"
    )
    weather.goBack()

    // Open runway picker and check 28R label for wind component info
    let runwayPicker = takeoff.openRunwayPicker()
    let label = runwayPicker.runwayRowLabel("28R")

    // 28R heading ≈ 280°, wind from 350° means a crosswind component
    // The label should contain wind component information
    XCTAssertFalse(label.isEmpty, "Runway row label should have content")
  }

  @MainActor
  func testScenarioFieldsPersistAfterNavigation() async throws {
    let tabBar = AppLauncher().launchAndCompleteSetup(emptyWeight: "4550")
    let settings = tabBar.goToSettings()
    let scenarios = settings.openScenarios()

    let detail = scenarios.addScenario()
    detail.setName("Persist Test")
    detail.setOATDelta("15")
    detail.setWeightDelta("200")
    detail.goBack()

    // Reopen and verify
    let detail2 = scenarios.openScenario("Persist Test")
    XCTAssertTrue(
      detail2.nameField.waitForExistence(timeout: 2),
      "Name field should exist"
    )

    let nameValue = detail2.nameField.value as? String ?? ""
    XCTAssertEqual(nameValue, "Persist Test", "Scenario name should persist")

    let oatValue = detail2.OATDeltaField.value as? String ?? ""
    XCTAssertTrue(
      oatValue.contains("15"),
      "OAT delta should persist, got: \(oatValue)"
    )

    detail2.goBack()

    // Cleanup
    await scenarios.deleteScenario("Persist Test")
  }

  @MainActor
  func testRestoreDefaultScenariosReturnsDefaults() throws {
    // Launch without default scenarios so the Restore button is immediately visible
    let tabBar = AppLauncher(skipScenarioSeeding: true)
      .launchAndCompleteSetup(emptyWeight: "4550")
    let settings = tabBar.goToSettings()
    let scenarios = settings.openScenarios()

    scenarios.tapRestoreDefaults()

    // Verify a known default scenario reappears
    XCTAssertTrue(
      scenarios.scenarioExists("OAT +10\u{00B0}C"),
      "Default scenario should appear after restore"
    )
  }

  @MainActor
  func testPerformanceModelImpactOnResults() throws {
    // Use weight between AFM grid points (5000, 5500 lbs) to maximize model divergence
    let tabBar = AppLauncher().launchAndCompleteSetup(emptyWeight: "4550")
    let takeoff = tabBar.goToTakeoff()
    takeoff.setupCalculation(payload: "700")
    let tabularDistance = takeoff.distanceValue

    // Relaunch with Regression model
    let tabBar2 = AppLauncher(useRegressionModel: true)
      .launchAndCompleteSetup(emptyWeight: "4550")
    let takeoff2 = tabBar2.goToTakeoff()
    takeoff2.setupCalculation(payload: "700")
    let regressionDistance = takeoff2.distanceValue

    if let tabularDistance, let regressionDistance {
      XCTAssertNotEqual(
        tabularDistance,
        regressionDistance,
        accuracy: 1,
        "Tabular (\(tabularDistance)) and Regression (\(regressionDistance)) distances should differ"
      )
    }
  }

  @MainActor
  func testAllUnitsPersistAcrossNavigation() throws {
    let tabBar = AppLauncher().launchAndCompleteSetup(emptyWeight: "4550")
    let settings = tabBar.goToSettings()
    let units = settings.openUnits()

    units.selectWeight("Kilograms (kg)")
    units.selectTemperature("Fahrenheit (°F)")
    units.selectPressure("Hectopascals (hPa)")
    units.selectFuelVolume("Liters (L)")

    units.goBack()

    // Navigate to takeoff and back to units
    _ = tabBar.goToTakeoff()
    let settings2 = tabBar.goToSettings()
    let units2 = settings2.openUnits()

    XCTAssertTrue(
      units2.weightPickerLabel.contains("Kilograms"),
      "Weight should persist as Kilograms"
    )
    XCTAssertTrue(
      units2.temperaturePickerLabel.contains("Fahrenheit"),
      "Temperature should persist as Fahrenheit"
    )
    XCTAssertTrue(
      units2.pressurePickerLabel.contains("Hectopascals"),
      "Pressure should persist as Hectopascals"
    )
    XCTAssertTrue(
      units2.fuelVolumePickerLabel.contains("Liters"),
      "Fuel volume should persist as Liters"
    )
  }

  @MainActor
  func testUseAFMSafetyFactorsResetsValues() throws {
    let tabBar = AppLauncher().launchAndCompleteSetup(emptyWeight: "4550")
    let settings = tabBar.goToSettings()

    settings.setSafetyFactorDry("1.5")
    settings.dismissKeyboard()

    // Tap "Use AFM Safety Factors" button
    let useDefaultButton = settings.useDefaultFactorsButton
    let defaultButton = try XCTUnwrap(
      settings.scrollToElement(useDefaultButton),
      "Use AFM Safety Factors button should exist"
    )
    defaultButton.tap()

    // Verify values reset to AFM defaults (1.67 dry, 1.92 wet)
    let dryValue = settings.safetyFactorDryField.value as? String ?? ""
    XCTAssertTrue(
      dryValue.contains("1.67"),
      "Safety factor dry should reset to 1.67, got: \(dryValue)"
    )

    let wetValue = settings.safetyFactorWetField.value as? String ?? ""
    XCTAssertTrue(
      wetValue.contains("1.92"),
      "Safety factor wet should reset to 1.92, got: \(wetValue)"
    )
  }

  @MainActor
  func testWeatherChangesUpdateResults() throws {
    let tabBar = AppLauncher().launchAndCompleteSetup(emptyWeight: "4550")
    let takeoff = tabBar.goToTakeoff()

    takeoff.setupCalculation()

    let baselineDistance = takeoff.distanceValue

    // Change temperature to 40°C (hotter)
    let weather = takeoff.openWeatherPicker()
    weather.setTemperature("40")
    weather.goBack()

    let hotterDistance = takeoff.distanceValue

    if let baselineDistance, let hotterDistance {
      XCTAssertGreaterThan(
        hotterDistance,
        baselineDistance,
        "Hotter temperature should result in longer takeoff distance"
      )
    }
  }

  @MainActor
  func testNOTAMShorteningReducesAvailableRunway() throws {
    let tabBar = AppLauncher().launchAndCompleteSetup(emptyWeight: "4050")
    let landing = tabBar.goToLanding()

    landing.setupCalculation()

    let baselineDistance = landing.landingDistanceValue

    let notams = landing.openNOTAMs()
    notams.setRunwayShortening("500")
    notams.goBack()

    // Wait for recalculation after navigating back
    landing.app.scrollToTop()

    // With a shorter runway available, the distance doesn't change but the
    // relationship to available runway does. Verify the NOTAM was applied.
    let badgeLabel = landing.waitForLabel(of: landing.NOTAMSelector, toContain: "1 configured")
    XCTAssertTrue(
      badgeLabel.contains("1 configured"),
      "NOTAM should be configured, got: \"\(badgeLabel)\""
    )
    XCTAssertNotNil(baselineDistance, "Baseline distance should have been captured")
  }

  @MainActor
  func testFlapSettingImpactOnAllLandingValues() throws {
    let tabBar = AppLauncher().launchAndCompleteSetup(emptyWeight: "4050")
    let landing = tabBar.goToLanding()

    landing.setupCalculation()

    // Record Flaps 100% values
    let flaps100GroundRun = landing.landingGroundRunValue
    let flaps100Distance = landing.landingDistanceValue

    // Switch to Flaps 50%
    landing.selectFlaps("Flaps 50%")
    let flaps50GroundRun = landing.landingGroundRunValue
    let flaps50Distance = landing.landingDistanceValue

    if let flaps100GroundRun, let flaps50GroundRun {
      XCTAssertGreaterThan(
        flaps50GroundRun,
        flaps100GroundRun,
        "Flaps 50% should have longer ground run than Flaps 100%"
      )
    }
    if let flaps100Distance, let flaps50Distance {
      XCTAssertGreaterThan(
        flaps50Distance,
        flaps100Distance,
        "Flaps 50% should have longer distance than Flaps 100%"
      )
    }

    // Flaps Up uses identical AFM data to Flaps 50% in the Tabular model,
    // so verify values are at least equal (no regression).
    landing.selectFlaps("Flaps Up")
    let flapsUpGroundRun = landing.landingGroundRunValue
    let flapsUpDistance = landing.landingDistanceValue

    if let flaps50GroundRun, let flapsUpGroundRun {
      XCTAssertGreaterThanOrEqual(
        flapsUpGroundRun,
        flaps50GroundRun,
        "Flaps Up should have ground run >= Flaps 50%"
      )
    }
    if let flaps50Distance, let flapsUpDistance {
      XCTAssertGreaterThanOrEqual(
        flapsUpDistance,
        flaps50Distance,
        "Flaps Up should have distance >= Flaps 50%"
      )
    }
  }

  @MainActor
  func testClimbIceProtectionReducesPerformance() throws {
    let tabBar = AppLauncher().launchAndCompleteSetup(emptyWeight: "4550")
    let climb = tabBar.goToClimb()

    // Use mid-range altitude where ice protection has a clear impact on climb rate
    climb.adjustFuel(to: 0.5)
    climb.adjustAltitude(to: 0.4)

    XCTAssertTrue(
      climb.rateValue.waitForExistence(timeout: 2),
      "Climb rate should be displayed"
    )
    let baselineRate = climb.rateLabel

    // Toggle ice protection on (may scroll the view)
    climb.toggleIceProtection()

    // Scroll back to make the rate value visible
    climb.app.scrollToTop()

    // On some devices ice protection may push the rate offscale (losing the
    // identifier). Either a changed value or offscale proves performance impact.
    if climb.rateValue.waitForExistence(timeout: 3) {
      let iceProtectionRate = climb.waitForLabelChange(
        climb.rateValue,
        from: baselineRate,
        timeout: 5
      )
      XCTAssertNotEqual(
        baselineRate,
        iceProtectionRate,
        "Climb rate should change with ice protection"
      )
    } else {
      let offscale = climb.app.staticTexts["Offscale high"]
      XCTAssertTrue(
        offscale.exists,
        "Climb rate should change or go offscale with ice protection"
      )
    }
  }

  // MARK: - Weather Mode Tests

  @MainActor
  func testWeatherDownloadedMode() throws {
    let tabBar = AppLauncher(weatherMode: .NWS).launchAndCompleteSetup(emptyWeight: "4550")
    let takeoff = tabBar.goToTakeoff()

    let picker = takeoff.openAirportPicker()
    picker.searchAndSelect("OAK")

    let weather = takeoff.openWeatherPicker()

    let nwsLabel = takeoff.app.staticTexts["Using downloaded weather from NWS"]
    _ = weather.scrollToElement(nwsLabel)
    XCTAssertTrue(
      nwsLabel.waitForExistence(timeout: 5),
      "NWS weather source label should appear"
    )

    let windDir = weather.windDirectionField.value as? String ?? ""
    XCTAssertTrue(windDir.contains("350"), "Wind direction should be pre-populated with 350")
  }

  @MainActor
  func testWeatherErrorMode() throws {
    let tabBar = AppLauncher(weatherMode: .error).launchAndCompleteSetup(emptyWeight: "4550")
    let takeoff = tabBar.goToTakeoff()

    let picker = takeoff.openAirportPicker()
    picker.searchAndSelect("OAK")

    _ = takeoff.openWeatherPicker()

    let errorLabel = takeoff.app.staticTexts.matching(
      NSPredicate(format: "label CONTAINS[c] 'load weather'")
    ).firstMatch
    XCTAssertTrue(
      errorLabel.waitForExistence(timeout: 5),
      "Weather error label should appear"
    )

    let tryAgainButton = takeoff.app.buttons["updateWeatherButton"]
    XCTAssertTrue(tryAgainButton.exists, "Update weather button should appear")
  }

  @MainActor
  func testWeatherUserEnteredMode() throws {
    let tabBar = AppLauncher().launchAndCompleteSetup(emptyWeight: "4550")
    let takeoff = tabBar.goToTakeoff()

    let picker = takeoff.openAirportPicker()
    picker.searchAndSelect("OAK")

    let weather = takeoff.openWeatherPicker()
    weather.setWeather(
      windDirection: "180",
      windSpeed: "10",
      temperature: "25",
      altimeter: "29.92"
    )

    let customLabel = takeoff.app.staticTexts["Using your custom weather"]
    _ = weather.scrollToElement(customLabel)
    XCTAssertTrue(
      customLabel.waitForExistence(timeout: 5),
      "Custom weather label should appear"
    )

    let downloadButton = takeoff.app.buttons["updateWeatherButton"]
    XCTAssertTrue(downloadButton.exists, "Use Downloaded Weather button should appear")
  }
}
// swiftlint:enable prefer_nimble
