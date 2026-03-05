import XCTest

final class UnitsSettingsPage: BasePage {

  // MARK: - Pickers

  var weightPicker: XCUIElement { app.buttons["weightUnitPicker"] }
  var fuelVolumePicker: XCUIElement { app.buttons["fuelVolumeUnitPicker"] }
  var temperaturePicker: XCUIElement { app.buttons["temperatureUnitPicker"] }
  var pressurePicker: XCUIElement { app.buttons["pressureUnitPicker"] }
  var runwayLengthPicker: XCUIElement { app.buttons["runwayLengthUnitPicker"] }
  var distancePicker: XCUIElement { app.buttons["distanceUnitPicker"] }
  var heightPicker: XCUIElement { app.buttons["heightUnitPicker"] }
  var speedPicker: XCUIElement { app.buttons["speedUnitPicker"] }

  // MARK: - Queries

  var weightPickerLabel: String {
    scrollToElement(weightPicker)?.label ?? ""
  }
  var temperaturePickerLabel: String {
    scrollToElement(temperaturePicker)?.label ?? ""
  }
  var pressurePickerLabel: String {
    scrollToElement(pressurePicker)?.label ?? ""
  }
  var fuelVolumePickerLabel: String {
    scrollToElement(fuelVolumePicker)?.label ?? ""
  }

  // MARK: - Actions

  func selectWeight(_ unit: String) {
    guard let picker = scrollToElement(weightPicker) else { return }
    picker.tap()
    app.buttons[unit].tap()
  }

  func selectFuelVolume(_ unit: String) {
    guard let picker = scrollToElement(fuelVolumePicker) else { return }
    picker.tap()
    app.buttons[unit].tap()
  }

  func selectTemperature(_ unit: String) {
    guard let picker = scrollToElement(temperaturePicker) else { return }
    picker.tap()
    app.buttons[unit].tap()
  }

  func selectPressure(_ unit: String) {
    guard let picker = scrollToElement(pressurePicker) else { return }
    picker.tap()
    app.buttons[unit].tap()
  }

  func selectFuelDensity(_ unit: String) {
    let picker = app.buttons["fuelDensityUnitPicker"]
    guard let picker = scrollToElement(picker) else { return }
    picker.tap()
    app.buttons[unit].tap()
  }

  func goBack() {
    tapBackButton()
  }
}
