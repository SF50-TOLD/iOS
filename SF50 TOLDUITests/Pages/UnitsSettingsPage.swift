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
    select(unit, in: weightPicker)
  }

  func selectFuelVolume(_ unit: String) {
    select(unit, in: fuelVolumePicker)
  }

  func selectTemperature(_ unit: String) {
    select(unit, in: temperaturePicker)
  }

  func selectPressure(_ unit: String) {
    select(unit, in: pressurePicker)
  }

  func selectFuelDensity(_ unit: String) {
    select(unit, in: app.buttons["fuelDensityUnitPicker"])
  }

  func goBack() {
    tapBackButton()
  }

  /// Reveal `picker`, open its menu, and choose `unit`.
  ///
  /// Opening a `MenuPickerStyle` picker is a single tap that iPad/Liquid Glass
  /// can drop, leaving the menu closed; escalate the tap until the option
  /// appears before selecting it.
  private func select(_ unit: String, in picker: XCUIElement) {
    guard let picker = scrollToElement(picker) else {
      XCTFail("Unit picker should be reachable")
      return
    }
    let option = app.buttons[unit]
    let opened = picker.tap(
      untilExists: option,
      using: XCUIElement.TapStrategy.escalating
    )
    XCTAssertTrue(opened, "Unit option \"\(unit)\" should appear after opening the picker")
    forceTap(option)
  }
}
