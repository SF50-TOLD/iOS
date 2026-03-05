// swiftlint:disable prefer_nimble
import XCTest

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
    app.collectionViews.firstMatch.swipeDown()
    let button = scrollToElement(flapsButton)
    XCTAssertNotNil(button, "Flaps button should exist")
    button!.tap()
    app.buttons[flapSetting].tap()
    // Wait for async recalculation to propagate
    Thread.sleep(forTimeInterval: 1.0)
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
    let airportPicker = app.segmentedControls["airportListPicker"]
    tapAndEnsureNavigation(element: selector!, expectedElement: airportPicker)
    return AirportPickerPage(app: app)
  }

  func openRunwayPicker() -> RunwayPickerPage {
    let selector = scrollToElement(runwaySelector)
    XCTAssertNotNil(selector, "Runway selector should be accessible")
    selector!.tap()
    return RunwayPickerPage(app: app)
  }

  func openWeatherPicker() -> WeatherPickerPage {
    app.scrollToTop()
    let selector = scrollToElement(weatherSelector)
    XCTAssertNotNil(selector, "Weather selector should be accessible")
    selector!.tap()
    return WeatherPickerPage(app: app)
  }

  func openNOTAMs() -> NOTAMPage {
    let selector = scrollToElement(NOTAMSelector)
    XCTAssertTrue(
      NOTAMSelector.waitForExistence(timeout: 2),
      "NOTAM selector should exist"
    )
    selector?.tap()
    return NOTAMPage(app: app)
  }

  func openReport() -> ReportViewerPage {
    let reportButton = scrollToElement(app.buttons["generateLandingReportButton"])
    XCTAssertNotNil(reportButton, "Report button should be accessible")
    reportButton!.tap()
    return ReportViewerPage(app: app, title: "Landing Report")
  }

  func openGoAroundProfile() -> GoAroundProfilePage {
    let button = scrollToElement(app.buttons["showGoAroundProfileButton"])
    XCTAssertNotNil(button, "Show Go-Around button should be accessible")
    XCTAssertTrue(button!.isEnabled, "Show Go-Around button should be enabled")
    button!.tap()
    return GoAroundProfilePage(app: app)
  }

  func openAdjustments() -> LandingAdjustmentsPage {
    let link = scrollToElement(
      app.descendants(matching: .any)["landingAdjustmentsLink"].firstMatch
    )
    XCTAssertNotNil(link, "Landing adjustments link should be accessible")
    link!.tap()
    return LandingAdjustmentsPage(app: app)
  }

  func openLandingMap() -> RunwayMapPage {
    let button = scrollToElement(app.buttons["showLandingMapButton"])
    XCTAssertNotNil(button, "Show Landing Map button should be accessible")
    button!.tap()
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
// swiftlint:enable prefer_nimble
