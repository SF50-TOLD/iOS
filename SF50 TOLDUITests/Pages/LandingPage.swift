import XCTest
import XCUITestKit

final class LandingPage: BasePage {

  // MARK: - Elements

  var payloadField: XCUIElement { app.textFields["Payload"].firstMatch }
  var fuelField: XCUIElement { app.textFields["Landing Fuel"].firstMatch }
  var flapsButton: XCUIElement {
    app.buttons.matching(NSPredicate(format: "label CONTAINS 'Flaps'")).firstMatch
  }
  var VREFAdditiveField: XCUIElement { app.textFields["VREFAdditiveField"] }
  var airportSelector: XCUIElement {
    app.descendants(matching: .any)["airportSelector"].firstMatch
  }
  var runwaySelector: XCUIElement {
    app.descendants(matching: .any)["runwaySelector"].firstMatch
  }
  var weatherSelector: XCUIElement {
    app.descendants(matching: .any)["weatherSelector"].firstMatch
  }
  var NOTAMSelector: XCUIElement {
    app.descendants(matching: .any)["NOTAMsSelector"].firstMatch
  }

  // MARK: - Result Properties

  var VREFValue: String {
    let element = scrollToElement(app.staticTexts["VREFValue"])
    return element?.label ?? ""
  }

  var landingGroundRunValue: Double? {
    let element = scrollToElement(app.staticTexts["landingGroundRunValue"])
    guard let element else { return nil }
    return extractNumericValue(from: element.label)
  }

  var landingDistanceValue: Double? {
    let element = scrollToElement(app.staticTexts["landingDistanceValue"])
    guard let element else { return nil }
    return extractNumericValue(from: element.label)
  }

  var goAroundClimbGradient: String {
    let element = scrollToElement(app.staticTexts["goAroundClimbGradientValue"])
    return element?.label ?? ""
  }

  var NOTAMBadgeLabel: String {
    let button = scrollToElement(NOTAMSelector)
    return button?.label ?? ""
  }

  // MARK: - Loadout Actions

  func setPayload(_ value: String) {
    let field = scrollToElement(payloadField)
    XCTAssertNotNil(field, "Payload field should be accessible")
    field!.clearAndType(value, app: app)
  }

  func setFuel(_ value: String) {
    let field = scrollToElement(fuelField)
    XCTAssertNotNil(field, "Fuel field should be accessible")
    field!.clearAndType(value, app: app)
  }

  func selectFlaps(_ flapSetting: String) {
    let resultValue = app.staticTexts["landingDistanceValue"]
    let previousDistance = scrollToElement(resultValue)?.label ?? ""
    app.collectionViews.firstMatch.swipeDown()
    let button = scrollToElement(flapsButton)
    XCTAssertNotNil(button, "Flaps button should exist")
    let option = app.buttons[flapSetting]
    // Opening the menu is a single tap that Liquid Glass can drop, leaving the
    // menu closed; escalate the tap until the option appears.
    let opened = button!.tap(
      untilExists: option,
      using: XCUIElement.TapStrategy.escalating
    )
    XCTAssertTrue(
      opened,
      "Flaps option \"\(flapSetting)\" should appear after opening the menu"
    )
    forceTap(option)
    // Wait for the asynchronous recalculation to update the landing distance.
    scrollToElement(resultValue)
    _ = waitForLabelChange(resultValue, from: previousDistance, timeout: 2)
  }

  func setVREFAdditive(_ value: String) {
    app.scrollToTop()
    let field = scrollToElement(VREFAdditiveField)
    XCTAssertNotNil(field, "VREF additive field should be accessible")
    field!.clearAndType(value, app: app)
    dismissKeyboard()
  }

  // MARK: - Navigation

  func openAirportPicker() -> AirportPickerPage {
    let selector = scrollToElement(airportSelector)
    XCTAssertNotNil(selector, "Airport selector should be accessible")
    ensureHittable(selector!)
    tapAndEnsureNavigation(element: selector!, expectedElement: app.airportListPicker())
    return AirportPickerPage(app: app)
  }

  func openRunwayPicker() -> RunwayPickerPage {
    let selector = scrollToElement(runwaySelector)
    XCTAssertNotNil(selector, "Runway selector should be accessible")
    let anyRunwayRow = app.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH 'runwayRow-'")
    ).firstMatch
    tapAndEnsureNavigation(element: selector!, expectedElement: anyRunwayRow)
    return RunwayPickerPage(app: app)
  }

  func openWeatherPicker() -> WeatherPickerPage {
    app.scrollToTop()
    let selector = scrollToElement(weatherSelector)
    XCTAssertNotNil(selector, "Weather selector should be accessible")
    let windField = app.textFields["windDirectionField"].firstMatch
    tapAndEnsureNavigation(element: selector!, expectedElement: windField)
    let weatherPicker = WeatherPickerPage(app: app)
    weatherPicker.dismissInProgressLoad()
    return weatherPicker
  }

  func openNOTAMs() -> NOTAMPage {
    let selector = scrollToElement(NOTAMSelector)
    XCTAssertNotNil(selector, "NOTAM selector should be accessible")
    tapAndEnsureNavigation(
      element: selector!,
      expectedElement: app.buttons["clearNOTAMsButton"]
    )
    return NOTAMPage(app: app)
  }

  func openReport() -> ReportViewerPage {
    let reportButton = scrollToElement(app.buttons["generateLandingReportButton"])
    XCTAssertNotNil(reportButton, "Report button should be accessible")
    tapAndEnsureNavigation(
      element: reportButton!,
      expectedElement: app.navigationBars["Landing Report"]
    )
    return ReportViewerPage(app: app, title: "Landing Report")
  }

  func openGoAroundProfile() -> GoAroundProfilePage {
    let button = scrollToElement(app.buttons["showGoAroundProfileButton"])
    XCTAssertNotNil(button, "Show Go-Around button should be accessible")
    XCTAssertTrue(button!.isEnabled, "Show Go-Around button should be enabled")
    forceTap(button!)
    return GoAroundProfilePage(app: app)
  }

  func openAdjustments() -> LandingAdjustmentsPage {
    let link = scrollToElement(
      app.descendants(matching: .any)["landingAdjustmentsLink"].firstMatch
    )
    XCTAssertNotNil(link, "Landing adjustments link should be accessible")
    tapAndEnsureNavigation(
      element: link!,
      expectedElement: app.navigationBars["Landing Adjustments"]
    )
    return LandingAdjustmentsPage(app: app)
  }

  func openLandingMap() -> RunwayMapPage {
    let button = scrollToElement(app.buttons["showLandingMapButton"])
    XCTAssertNotNil(button, "Show Landing Map button should be accessible")
    forceTap(button!)
    return RunwayMapPage(app: app)
  }

  // MARK: - Composites

  func selectAirportRunwayWeather(
    airport: String = "OAK",
    runway: String = "28R"
  ) {
    let picker = openAirportPicker()
    picker.searchAndSelect(airport)

    let runwayPicker = openRunwayPicker()
    runwayPicker.selectRunway(runway)

    let weather = openWeatherPicker()
    weather.setWeather(
      windDirection: "350",
      windSpeed: "15",
      temperature: "21",
      altimeter: "30.05"
    )
    weather.goBack()
  }

  func setupCalculation(
    payload: String = "450",
    fuel: String = "0",
    airport: String = "OAK",
    runway: String = "28R"
  ) {
    setPayload(payload)
    setFuel(fuel)
    selectAirportRunwayWeather(airport: airport, runway: runway)
  }
}
