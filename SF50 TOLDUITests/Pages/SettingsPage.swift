// swiftlint:disable prefer_nimble
import XCTest
import XCUITestKit

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
    ensureHittable(aircraftTypePicker)
    let option = app.buttons[model]
    // Opening the picker is a single tap that iPad/Liquid Glass can drop;
    // retry until the option appears before selecting it.
    let opened = aircraftTypePicker.tap(until: { option.waitForExistence(timeout: 5) })
    XCTAssertTrue(opened, "Aircraft option \"\(model)\" should appear after opening the picker")
    forceTap(option)
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
    forceTap(toggle!)

    // On iOS 26, MenuPickerStyle options may render as menuItems or buttons
    let menuItem = app.menuItems[model].firstMatch
    let button = app.buttons[model].firstMatch
    let popUp = app.popUpButtons[model].firstMatch
    if menuItem.waitForExistence(timeout: 2) {
      forceTap(menuItem)
    } else if button.waitForExistence(timeout: 2) {
      forceTap(button)
    } else if popUp.waitForExistence(timeout: 2) {
      forceTap(popUp)
    } else {
      // Tap any descendant matching the model name
      let any = app.descendants(matching: .any)[model].firstMatch
      XCTAssertTrue(
        any.waitForExistence(timeout: 2),
        "Could not find '\(model)' option in any form"
      )
      forceTap(any)
    }
  }

  func selectTimeZone(_ zone: String) {
    let picker = scrollToElement(timeZoneDisplayPicker)
    XCTAssertNotNil(picker, "Time zone picker should exist")
    let option = app.buttons[zone]
    // Opening the picker is a single tap that iPad/Liquid Glass can drop;
    // retry until the option appears before selecting it.
    let opened = picker!.tap(until: { option.waitForExistence(timeout: 5) })
    XCTAssertTrue(opened, "Time zone option \"\(zone)\" should appear after opening the picker")
    forceTap(option)
  }

  // MARK: - Navigation

  func openScenarios() -> ScenariosSettingsPage {
    let link = scrollToElement(app.buttons["scenariosNavigationLink"])
    XCTAssertNotNil(link, "Scenarios link should exist")
    forceTap(link!)
    return ScenariosSettingsPage(app: app)
  }

  func openUnits() -> UnitsSettingsPage {
    let link = scrollToElement(app.buttons["unitsNavigationLink"])
    XCTAssertNotNil(link, "Units link should exist")
    forceTap(link!)
    return UnitsSettingsPage(app: app)
  }

  func openTerrain() -> TerrainSettingsPage {
    let link = scrollToElement(app.buttons["terrainNavigationLink"])
    XCTAssertNotNil(link, "Terrain link should exist")
    forceTap(link!)
    return TerrainSettingsPage(app: app)
  }
}
// swiftlint:enable prefer_nimble
