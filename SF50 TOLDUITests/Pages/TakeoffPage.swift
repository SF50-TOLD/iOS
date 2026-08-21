import XCTest
import XCUITestKit

final class TakeoffPage: BasePage {

  // MARK: - Elements

  var payloadField: XCUIElement { app.textFields["payloadField"].firstMatch }
  var fuelField: XCUIElement { app.textFields["fuelField"].firstMatch }
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
    field!.clearAndType(value, app: app, replacingSelection: true, verifying: true)
  }

  func setFuel(_ value: String) {
    let field = scrollToElement(fuelField)
    XCTAssertNotNil(field, "Fuel field should be accessible")
    field!.clearAndType(value, app: app, replacingSelection: true, verifying: true)
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
    forceTap(selector!)
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
      expectedElement: app.textFields["obstacleHeightField"].firstMatch
    )
    return NOTAMPage(app: app)
  }

  func openReport() -> ReportViewerPage {
    let reportButton = scrollToElement(app.buttons["generateTakeoffReportButton"])
    XCTAssertNotNil(reportButton, "Report button should be accessible")
    tapAndEnsureNavigation(
      element: reportButton!,
      expectedElement: app.navigationBars["Takeoff Report"]
    )
    return ReportViewerPage(app: app, title: "Takeoff Report")
  }

  func openClimbProfile() -> ClimbProfilePage {
    let button = scrollToElement(app.buttons["showClimbProfileButton"])
    XCTAssertNotNil(button, "Show Climb button should be accessible")
    XCTAssertTrue(button!.isEnabled, "Show Climb button should be enabled")
    tapAndEnsureNavigation(
      element: button!,
      expectedElement: app.navigationBars["Climb Profile"]
    )
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
