import XCTest
import XCUITestKit

final class WelcomePage: BasePage {

  var modelPicker: XCUIElement { app.segmentedControls["modelPicker"] }
  var emptyWeightField: XCUIElement { app.textFields["emptyWeightField"] }
  var continueButton: XCUIElement { app.buttons["continueButton"] }
  var thrustScheduleToggle: XCUIElement { app.switches["updatedThrustScheduleToggle"] }

  /// Defers the nav-data loader if it is up. The loader and the welcome screen take each other's
  /// place, so a welcome screen already showing means there is no loader to wait for.
  func handleDatabaseLoaderIfNeeded() {
    let deferButton = app.buttons["deferDataButton"]
    if !continueButton.exists, deferButton.wait(timeout: 2) {
      forceTap(deferButton)
    }
  }

  /// Waits for the welcome screen to be fully loaded before interacting.

  func waitForReady() {
    XCTAssertTrue(
      continueButton.wait(timeout: 5),
      "Welcome screen should be fully loaded"
    )
  }

  func selectModel(_ model: String) {
    XCTAssertTrue(
      modelPicker.wait(timeout: 5),
      "Model picker should be accessible"
    )
    let button = modelPicker.buttons[model]
    XCTAssertTrue(button.wait(timeout: 2), "\(model) button should exist in picker")
    ensureHittable(button)
    tapUntilSelected(button)
  }

  func setEmptyWeight(_ weight: String) {
    XCTAssertTrue(
      emptyWeightField.wait(timeout: 2),
      "Empty weight field should be accessible"
    )
    emptyWeightField.enter(weight, app: app)
  }

  func toggleThrustSchedule() {
    XCTAssertTrue(
      thrustScheduleToggle.wait(timeout: 2),
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
      continueButton.wait(timeout: 5),
      "Continue button should be tappable"
    )
    ensureHittable(continueButton)
    tapAndEnsureNavigation(
      element: continueButton,
      expectedElement: app.textFields["payloadField"].firstMatch
    )

    // If the data loader appears after setup, defer it. It takes the tab view's place, so it
    // cannot be up while the payload field is.
    let payloadField = app.textFields["payloadField"].firstMatch
    let deferButton = app.buttons["deferDataButton"]
    if !payloadField.exists, deferButton.wait(timeout: 3) {
      forceTap(deferButton)
    }

    XCTAssertTrue(
      payloadField.wait(timeout: 10),
      "Payload field should appear after setup"
    )
    return TabBarPage(app: app)
  }

  /// Taps Continue when the nav-data loader is expected to gate entry, landing
  /// on the consent screen rather than the main tab view.
  func tapContinueExpectingConsent() -> LoadingConsentPage {
    if app.keyboards.count > 0 {  // swiftlint:disable:this empty_count
      app.swipeDown()
    }
    XCTAssertTrue(
      continueButton.wait(timeout: 5),
      "Continue button should be tappable"
    )
    ensureHittable(continueButton)
    tapAndEnsureNavigation(
      element: continueButton,
      expectedElement: app.buttons["downloadDataButton"]
    )
    return LoadingConsentPage(app: app)
  }
}
