// swiftlint:disable prefer_nimble
import XCTest
import XCUITestKit

final class ScenariosSettingsPage: BasePage {

  /// Default scenario names from `Scenario.defaultScenarios()`.
  private static let defaultScenarioNames = [
    "OAT +10\u{00B0}C",
    "OAT -10\u{00B0}C",
    "Wind Speed +10 kn",
    "Wind Speed -10 kn",
    "Weight +200 lbs",
    "Weight -200 lbs",
    "Flaps 50"
  ]

  func addScenario() -> ScenarioDetailPage {
    var addButton = app.buttons["Add Scenario"].firstMatch
    var scrollAttempts = 0
    while !addButton.exists && scrollAttempts < 3 {
      app.swipeUp()
      scrollAttempts += 1
      addButton = app.buttons["Add Scenario"].firstMatch
    }
    XCTAssertTrue(
      addButton.waitForExistence(timeout: 2),
      "Add Scenario button should exist"
    )
    forceTap(addButton)
    return ScenarioDetailPage(app: app)
  }

  func scenarioExists(_ name: String) -> Bool {
    let text = app.staticTexts[name]

    // Wait briefly for data to render after restore
    if text.waitForExistence(timeout: 3) { return true }

    // Scroll to top before searching downward
    app.scrollToTop()
    if text.waitForExistence(timeout: 1) { return true }

    var findAttempts = 0
    while !text.exists && findAttempts < 10 {
      app.swipeUp()
      findAttempts += 1
    }
    return text.exists
  }

  func deleteScenario(_ name: String) {
    let deleteButton = app.buttons["Delete"]

    for _ in 0..<5 {
      let text = app.staticTexts[name].firstMatch
      guard scrollToElement(text) != nil else { return }

      // Swipe on the containing cell/button row rather than the text itself
      // to reliably trigger SwiftUI's .onDelete modifier
      let cell = app.cells.containing(.staticText, identifier: name).firstMatch
      let target = cell.exists ? cell : text
      target.swipeLeft(velocity: .fast)
      if deleteButton.waitForExistence(timeout: 1) { break }
    }

    if deleteButton.waitForExistence(timeout: 2) {
      // The Delete button (and any confirmation) disappears once the tap
      // registers; a single forceTap is intermittently dropped on iPad, so
      // retry until it's gone.
      deleteButton.tap(until: { deleteButton.waitForNonExistence(timeout: 2) })
    }
  }

  func openScenario(_ name: String) -> ScenarioDetailPage {
    // Mirror the search strategy from `scenarioExists`: wait briefly for the
    // row to appear in case the SwiftData write + List refresh after goBack
    // is still settling, then scroll to find it if it landed below the fold.
    XCTAssertTrue(scenarioExists(name), "Scenario \(name) should exist")
    let text = app.staticTexts[name]
    forceTap(text)
    return ScenarioDetailPage(app: app)
  }

  func deleteAllScenarios() {
    // Delete each default scenario by name. Each name may appear in both the
    // takeoff and landing sections, so loop until it no longer exists.
    for name in Self.defaultScenarioNames {
      app.scrollToTop()
      var iterations = 0
      while app.staticTexts[name].exists && iterations < 5 {
        deleteScenario(name)
        app.scrollToTop()
        iterations += 1
      }
    }
  }

  func tapRestoreDefaults() {
    var button = app.buttons["Restore Default Scenarios"].firstMatch
    var scrollAttempts = 0
    while !button.exists && scrollAttempts < 5 {
      app.swipeUp()
      scrollAttempts += 1
      button = app.buttons["Restore Default Scenarios"].firstMatch
    }
    XCTAssertTrue(button.exists, "Restore Default Scenarios button should exist")
    forceTap(button)
  }

  func goBack() {
    tapBackButton()
  }
}
// swiftlint:enable prefer_nimble
