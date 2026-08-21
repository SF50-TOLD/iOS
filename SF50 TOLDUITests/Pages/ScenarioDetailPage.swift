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
    emptyNameField()
    nameField.clearAndType(name, app: app, replacingSelection: true, verifying: true)
    // Ends editing so the name binding commits before any subsequent action
    // (other field tap, back-nav, etc.). On iPad iOS 18.4 the first-responder
    // transfer from a plain TextField can drop the latest keystroke if we
    // don't explicitly resign first responder here.
    dismissKeyboard()
    XCTAssertEqual(nameField.value as? String, name, "Name field should hold the typed name")
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
      field.clearAndType(value, app: app, replacingSelection: true, verifying: true)
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

  /// Empties the name field before it is typed into.
  ///
  /// The measurement fields select their contents when they take focus, so typing over them
  /// replaces the value; a plain `TextField` does not, and typing into one appends. Nor can
  /// ``XCUIElement/clearAndType(_:app:perCharacter:doneButtonIdentifier:)`` tell the two apart
  /// here: it verifies a value with no digits in it by substring, which the appended
  /// "New ScenarioPersist Test" satisfies just as well as "Persist Test" does.
  private func emptyNameField() {
    let current = nameField.value as? String ?? ""
    guard current != nameField.placeholderValue, !current.isEmpty else { return }
    // Park the caret past the last character, then backspace the name away. A couple of extra
    // deletes cover caret-position slack and no-op once the field is empty. Typing without
    // first responder fails outright, so leave the field to `clearAndType`'s own
    // empty-then-type fallback if the tap does not take.
    nameField.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
    guard nameField.waitForKeyboardFocus() else { return }
    nameField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count + 2))
  }

  func goBack() {
    dismissKeyboard()
    tapBackButton()
    _ = app.navigationBars["Scenarios"].waitForExistence(timeout: 3)
  }
}
