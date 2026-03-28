// swiftlint:disable prefer_nimble
import XCTest

final class TakeoffPage: BasePage {

  // MARK: - Elements

  var payloadField: XCUIElement { app.textFields["Payload"].firstMatch }
  var fuelField: XCUIElement { app.textFields["Takeoff Fuel"].firstMatch }
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

  var groundRunValue: Double? {
    let element = scrollToElement(app.staticTexts["takeoffGroundRunValue"].firstMatch)
    guard let element else { return nil }
    return extractNumericValue(from: element.label)
  }

  var distanceValue: Double? {
    let element = scrollToElement(app.staticTexts["takeoffDistanceValue"].firstMatch)
    guard let element else { return nil }
    return extractNumericValue(from: element.label)
  }

  var vxClimbGradient: String {
    let element = scrollToElement(app.staticTexts["vxClimbGradientValue"])
    return element?.label ?? ""
  }

  var vxClimbRate: String {
    let element = scrollToElement(app.staticTexts["vxClimbRateValue"])
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

  // MARK: - Navigation

  func openAirportPicker() -> AirportPickerPage {
    let selector = scrollToElement(airportSelector)
    XCTAssertNotNil(selector, "Airport selector should be accessible")
    ensureHittable(selector!)
    let airportPicker = app.segmentedControls["airportListPicker"]
    tapAndEnsureNavigation(element: selector!, expectedElement: airportPicker)
    return AirportPickerPage(app: app)
  }

  func openRunwayPicker() -> RunwayPickerPage {
    let selector = scrollToElement(runwaySelector)
    XCTAssertNotNil(selector, "Runway selector should be accessible")
    forceTap(selector!)
    return RunwayPickerPage(app: app)
  }

  func openWeatherPicker() -> WeatherPickerPage {
    app.scrollToTop()
    let selector = scrollToElement(weatherSelector)
    XCTAssertNotNil(selector, "Weather selector should be accessible")
    forceTap(selector!)
    return WeatherPickerPage(app: app)
  }

  func openNOTAMs() -> NOTAMPage {
    let selector = scrollToElement(NOTAMSelector)
    XCTAssertTrue(
      NOTAMSelector.waitForExistence(timeout: 2),
      "NOTAM selector should exist"
    )
    if let selector { forceTap(selector) }
    return NOTAMPage(app: app)
  }

  func openReport() -> ReportViewerPage {
    let reportButton = scrollToElement(app.buttons["generateTakeoffReportButton"])
    XCTAssertNotNil(reportButton, "Report button should be accessible")
    forceTap(reportButton!)
    return ReportViewerPage(app: app, title: "Takeoff Report")
  }

  func openClimbProfile() -> ClimbProfilePage {
    let button = scrollToElement(app.buttons["showClimbProfileButton"])
    XCTAssertNotNil(button, "Show Climb button should be accessible")
    XCTAssertTrue(button!.isEnabled, "Show Climb button should be enabled")
    forceTap(button!)
    return ClimbProfilePage(app: app)
  }

  func openAdjustments() -> TakeoffAdjustmentsPage {
    let link = scrollToElement(
      app.descendants(matching: .any)["takeoffAdjustmentsLink"].firstMatch
    )
    XCTAssertNotNil(link, "Takeoff adjustments link should be accessible")
    forceTap(link!)
    return TakeoffAdjustmentsPage(app: app)
  }

  func openTakeoffMap() -> RunwayMapPage {
    let button = scrollToElement(app.buttons["showTakeoffMapButton"])
    XCTAssertNotNil(button, "Show Takeoff Map button should be accessible")
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
// swiftlint:enable prefer_nimble
