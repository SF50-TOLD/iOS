// swiftlint:disable prefer_nimble
import XCTest

final class SettingsPage: BasePage {

  // MARK: - Elements

  var aircraftTypePicker: XCUIElement {
    app.descendants(matching: .any)["aircraftTypePicker"].firstMatch
  }
  var thrustScheduleToggle: XCUIElement { app.switches["updatedThrustScheduleToggle"] }
  var weightField: XCUIElement { app.textFields["weightField"] }
  var safetyFactorDryField: XCUIElement { app.textFields["safetyFactorDryField"] }
  var safetyFactorWetField: XCUIElement { app.textFields["safetyFactorWetField"] }
  var selectModelToggle: XCUIElement { app.buttons["selectModelToggle"] }
  var timeZoneDisplayPicker: XCUIElement {
    app.descendants(matching: .any)["timeZoneDisplayPicker"].firstMatch
  }
  var useDefaultFactorsButton: XCUIElement { app.buttons["useDefaultFactorsButton"] }
  var isThrustScheduleToggleVisible: Bool {
    thrustScheduleToggle.waitForExistence(timeout: 1)
  }

  // MARK: - Actions

  func selectAircraftModel(_ model: String) {
    XCTAssertTrue(aircraftTypePicker.waitForExistence(timeout: 2), "Aircraft picker should exist")
    aircraftTypePicker.tap()
    app.buttons[model].tap()
  }

  func setEmptyWeight(_ weight: String) {
    XCTAssertTrue(weightField.waitForExistence(timeout: 2), "Weight field should exist")
    weightField.clearAndType(weight, app: app)
  }

  func setSafetyFactorDry(_ value: String) {
    XCTAssertTrue(
      safetyFactorDryField.waitForExistence(timeout: 2),
      "Safety factor dry field should exist"
    )
    safetyFactorDryField.clearAndType(value, app: app)
  }

  func selectPerformanceModel(_ model: String) {
    let toggle = scrollToElement(selectModelToggle)
    XCTAssertNotNil(toggle, "Model toggle should exist")
    toggle!.tap()

    // On iOS 26, MenuPickerStyle options may render as menuItems or buttons
    let menuItem = app.menuItems[model].firstMatch
    let button = app.buttons[model].firstMatch
    let popUp = app.popUpButtons[model].firstMatch
    if menuItem.waitForExistence(timeout: 2) {
      menuItem.tap()
    } else if button.waitForExistence(timeout: 2) {
      button.tap()
    } else if popUp.waitForExistence(timeout: 2) {
      popUp.tap()
    } else {
      // Tap any descendant matching the model name
      let any = app.descendants(matching: .any)[model].firstMatch
      XCTAssertTrue(
        any.waitForExistence(timeout: 2),
        "Could not find '\(model)' option in any form"
      )
      any.tap()
    }
  }

  func selectTimeZone(_ zone: String) {
    let picker = scrollToElement(timeZoneDisplayPicker)
    XCTAssertNotNil(picker, "Time zone picker should exist")
    picker!.tap()
    if app.buttons[zone].exists {
      app.buttons[zone].tap()
    }
  }

  // MARK: - Navigation

  func openScenarios() -> ScenariosSettingsPage {
    let link = scrollToElement(app.buttons["scenariosNavigationLink"])
    XCTAssertNotNil(link, "Scenarios link should exist")
    link!.tap()
    return ScenariosSettingsPage(app: app)
  }

  func openUnits() -> UnitsSettingsPage {
    let link = scrollToElement(app.buttons["unitsNavigationLink"])
    XCTAssertNotNil(link, "Units link should exist")
    link!.tap()
    return UnitsSettingsPage(app: app)
  }

  func openTerrain() -> TerrainSettingsPage {
    let link = scrollToElement(app.buttons["terrainNavigationLink"])
    XCTAssertNotNil(link, "Terrain link should exist")
    link!.tap()
    return TerrainSettingsPage(app: app)
  }
}
// swiftlint:enable prefer_nimble
