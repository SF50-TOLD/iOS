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
    // escalate the tap until the option appears before selecting it.
    let opened = aircraftTypePicker.tap(
      untilExists: option,
      using: XCUIElement.TapStrategy.escalating
    )
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
    // On iOS 26 a MenuPickerStyle option renders as a menuItem or a button, and a
    // single Liquid Glass tap on the picker can be dropped. Open the menu,
    // re-tapping until an option appears in either form, then select it.
    let menuItem = app.menuItems[model].firstMatch
    let button = app.buttons[model].firstMatch
    let popUpButton = app.popUpButtons[model].firstMatch
    for _ in 0..<4 {
      if menuItem.exists || button.exists || popUpButton.exists { break }
      forceTap(toggle!)
      _ = menuItem.waitForExistence(timeout: 1)
    }
    let option = [menuItem, button, popUpButton].first(where: \.exists)
    XCTAssertNotNil(
      option,
      "Performance model option \"\(model)\" should appear after opening the picker"
    )
    forceTap(option!)
  }

  func selectTimeZone(_ zone: String) {
    revealTimeZonePicker()
    XCTAssertTrue(
      timeZoneDisplayPicker.waitForExistence(timeout: 2),
      "Time zone picker should exist"
    )
    ensureHittable(timeZoneDisplayPicker)
    let option = app.buttons[zone]
    // Opening the picker is a single tap that iPad/Liquid Glass can drop;
    // escalate the tap until the option appears before selecting it.
    let opened = timeZoneDisplayPicker.tap(
      untilExists: option,
      using: XCUIElement.TapStrategy.escalating
    )
    XCTAssertTrue(opened, "Time zone option \"\(zone)\" should appear after opening the picker")
    forceTap(option)
  }

  /// Reveal the Time Zone picker, whose row is lazily rendered near the bottom of
  /// the Settings form. `scrollToElement(_:)`'s collection-view scroll does not
  /// reach the iOS 26 Settings container, and a single whole-screen scroll can
  /// race the lazy render under load — so swipe the whole screen up, pausing for
  /// the row to materialize, until the picker is hittable.
  private func revealTimeZonePicker() {
    for _ in 0..<12 {
      if timeZoneDisplayPicker.isHittable { return }
      let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
      let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
      start.press(forDuration: 0.1, thenDragTo: end)
      _ = timeZoneDisplayPicker.waitForExistence(timeout: 0.6)
    }
  }

  // MARK: - Navigation

  func openScenarios() -> ScenariosSettingsPage {
    let link = scrollToElement(app.buttons["scenariosNavigationLink"])
    XCTAssertNotNil(link, "Scenarios link should exist")
    // The first tap on a Liquid Glass Form row can be dropped; escalate it until
    // the destination nav bar confirms the push happened.
    let pushed = link!.tap(
      untilExists: app.navigationBars["Scenarios"],
      using: XCUIElement.TapStrategy.escalating
    )
    XCTAssertTrue(pushed, "Scenarios screen should appear after tapping its link")
    return ScenariosSettingsPage(app: app)
  }

  func openUnits() -> UnitsSettingsPage {
    let link = scrollToElement(app.buttons["unitsNavigationLink"])
    XCTAssertNotNil(link, "Units link should exist")
    // The first tap on a Liquid Glass Form row can be dropped; escalate it until
    // the destination nav bar confirms the push happened.
    let pushed = link!.tap(
      untilExists: app.navigationBars["Units"],
      using: XCUIElement.TapStrategy.escalating
    )
    XCTAssertTrue(pushed, "Units screen should appear after tapping its link")
    return UnitsSettingsPage(app: app)
  }

  func openTerrain() -> TerrainSettingsPage {
    let link = scrollToElement(app.buttons["terrainNavigationLink"])
    XCTAssertNotNil(link, "Terrain link should exist")
    // The first tap on a Liquid Glass Form row can be dropped; escalate it until
    // the destination nav bar confirms the push happened.
    let pushed = link!.tap(
      untilExists: app.navigationBars["Terrain Data"],
      using: XCUIElement.TapStrategy.escalating
    )
    XCTAssertTrue(pushed, "Terrain screen should appear after tapping its link")
    return TerrainSettingsPage(app: app)
  }
}
// swiftlint:enable prefer_nimble
