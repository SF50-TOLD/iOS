// swiftlint:disable prefer_nimble
import XCTest

final class WeatherPickerPage: BasePage {

  // MARK: - Fields

  var windDirectionField: XCUIElement { app.textFields["windDirectionField"] }
  var windSpeedField: XCUIElement { app.textFields["windSpeedField"] }
  var tempField: XCUIElement { app.textFields["tempField"] }
  var altimeterField: XCUIElement { app.textFields["altimeterField"] }

  // MARK: - Actions

  func setWindDirection(_ value: String) {
    let field = scrollToElement(windDirectionField)
    XCTAssertNotNil(field, "Wind direction field should be accessible")
    field!.clearAndType(value, app: app)
  }

  func setWindSpeed(_ value: String) {
    let field = scrollToElement(windSpeedField)
    XCTAssertNotNil(field, "Wind speed field should be accessible")
    field!.clearAndType(value, app: app)
  }

  func setTemperature(_ value: String) {
    let field = scrollToElement(tempField)
    XCTAssertNotNil(field, "Temperature field should be accessible")
    field!.clearAndType(value, app: app)
  }

  func setAltimeter(_ value: String) {
    let field = scrollToElement(altimeterField)
    XCTAssertNotNil(field, "Altimeter field should be accessible")
    field!.clearAndType(value, app: app)
  }

  func setWeather(
    windDirection: String,
    windSpeed: String,
    temperature: String,
    altimeter: String
  ) {
    setWindDirection(windDirection)
    setWindSpeed(windSpeed)
    setTemperature(temperature)
    setAltimeter(altimeter)
  }

  func goBack() {
    dismissKeyboard()
    tapBackButton()
  }
}
// swiftlint:enable prefer_nimble
