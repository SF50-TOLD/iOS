// swiftlint:disable prefer_nimble
import XCTest

final class WelcomePage: BasePage {

  var modelPicker: XCUIElement { app.segmentedControls["modelPicker"] }
  var emptyWeightField: XCUIElement { app.textFields["emptyWeightField"] }
  var continueButton: XCUIElement { app.buttons["continueButton"] }
  var thrustScheduleToggle: XCUIElement { app.switches["updatedThrustScheduleToggle"] }

  func handleDatabaseLoaderIfNeeded() {
    let deferButton = app.buttons["deferDataButton"]
    if deferButton.waitForExistence(timeout: 2) {
      forceTap(deferButton)
    }
  }

  /// Waits for the welcome screen to be fully loaded before interacting.

  func waitForReady() {
    XCTAssertTrue(
      continueButton.waitForExistence(timeout: 5),
      "Welcome screen should be fully loaded"
    )
  }

  func selectModel(_ model: String) {
    XCTAssertTrue(
      modelPicker.waitForExistence(timeout: 5),
      "Model picker should be accessible"
    )
    let button = modelPicker.buttons[model]
    XCTAssertTrue(button.waitForExistence(timeout: 2), "\(model) button should exist in picker")
    ensureHittable(button)
    tapUntilSelected(button)
  }

  func setEmptyWeight(_ weight: String) {
    XCTAssertTrue(
      emptyWeightField.waitForExistence(timeout: 2),
      "Empty weight field should be accessible"
    )
    emptyWeightField.clearAndType(weight, app: app)
  }

  func toggleThrustSchedule() {
    XCTAssertTrue(
      thrustScheduleToggle.waitForExistence(timeout: 2),
      "Thrust schedule toggle should exist"
    )
    ensureHittable(thrustScheduleToggle)
    forceTap(thrustScheduleToggle)
  }

  func tapContinue() -> TabBarPage {
    // Dismiss keyboard if visible so continue button is tappable
    if app.keyboards.count > 0 {  // swiftlint:disable:this empty_count
      app.swipeDown()
    }
    XCTAssertTrue(
      continueButton.waitForExistence(timeout: 5),
      "Continue button should be tappable"
    )
    ensureHittable(continueButton)
    tapAndEnsureNavigation(element: continueButton, expectedElement: app.textFields["Payload"])

    // If the data loader appears after setup, defer it
    let deferButton = app.buttons["deferDataButton"]
    if deferButton.waitForExistence(timeout: 3) {
      forceTap(deferButton)
    }

    XCTAssertTrue(
      app.textFields["Payload"].waitForExistence(timeout: 10),
      "Payload field should appear after setup"
    )
    return TabBarPage(app: app)
  }
}
// swiftlint:enable prefer_nimble
