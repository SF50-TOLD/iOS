// swiftlint:disable prefer_nimble
import XCTest

final class ScenarioDetailPage: BasePage {

  // MARK: - Fields

  var nameField: XCUIElement { app.textFields["scenarioNameField"] }
  var OATDeltaField: XCUIElement { app.textFields["OATDeltaField"] }
  var weightDeltaField: XCUIElement { app.textFields["weightDeltaField"] }

  // MARK: - Actions

  func setName(_ name: String) {
    XCTAssertTrue(nameField.waitForExistence(timeout: 2), "Name field should exist")
    nameField.clearAndType(name, app: app)
  }

  func setOATDelta(_ value: String) {
    XCTAssertTrue(OATDeltaField.exists, "OAT delta field should exist")
    OATDeltaField.clearAndType(value, app: app)
  }

  func setWeightDelta(_ value: String) {
    XCTAssertTrue(weightDeltaField.exists, "Weight delta field should exist")
    weightDeltaField.clearAndType(value, app: app)
  }

  func goBack() {
    dismissKeyboard()
    tapBackButton()
    _ = app.navigationBars["Scenarios"].waitForExistence(timeout: 3)
  }
}
// swiftlint:enable prefer_nimble
