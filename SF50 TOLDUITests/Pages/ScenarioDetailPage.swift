import XCTest
import XCUITestKit

final class ScenarioDetailPage: BasePage {

  // MARK: - Fields

  var nameField: XCUIElement { app.textFields["scenarioNameField"] }
  var OATDeltaField: XCUIElement { app.textFields["OATDeltaField"] }
  var weightDeltaField: XCUIElement { app.textFields["weightDeltaField"] }

  // MARK: - Actions

  func setName(_ name: String) {
    XCTAssertTrue(nameField.wait(), "Name field should exist")
    nameField.clearAndType(name, app: app)
    // Ends editing so the name binding commits before any subsequent action
    // (other field tap, back-nav, etc.). On iPad iOS 18.4 the first-responder
    // transfer from a plain TextField can drop the latest keystroke if we
    // don't explicitly resign first responder here.
    dismissKeyboard()
  }

  func setOATDelta(_ value: String) {
    XCTAssertTrue(OATDeltaField.exists, "OAT delta field should exist")
    clearTypeAndVerify(OATDeltaField, value)
  }

  func setWeightDelta(_ value: String) {
    XCTAssertTrue(weightDeltaField.exists, "Weight delta field should exist")
    clearTypeAndVerify(weightDeltaField, value)
  }

  /// Types `value` into a numeric ``MeasurementField`` and verifies the
  /// committed value reflects the typed digits, retrying if a keystroke was
  /// dropped (intermittent on slower simulator configs). Ends editing first
  /// so the `FormatStyle`-backed field commits before it is read back.
  private func clearTypeAndVerify(_ field: XCUIElement, _ value: String, retries: Int = 3) {
    let digits = value.filter(\.isNumber)
    for attempt in 1...retries {
      field.clearAndType(value, app: app)
      dismissKeyboard()
      let shown = (field.value as? String ?? "").filter(\.isNumber)
      if shown.contains(digits) { return }
      XCTAssertNotEqual(
        attempt,
        retries,
        "Field did not accept \"\(value)\"; shows \"\(field.value as? String ?? "")\""
      )
    }
  }

  func goBack() {
    dismissKeyboard()
    tapBackButton()
    _ = app.navigationBars["Scenarios"].waitForExistence(timeout: 3)
  }
}
