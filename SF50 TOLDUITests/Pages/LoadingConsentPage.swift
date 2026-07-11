// swiftlint:disable prefer_nimble
import XCTest
import XCUITestKit

final class LoadingConsentPage: BasePage {

  var downloadButton: XCUIElement { app.buttons["downloadDataButton"] }
  var deferButton: XCUIElement { app.buttons["deferDataButton"] }

  func isDisplayed() -> Bool {
    downloadButton.waitForExistence(timeout: 5)
  }

  func deferUntilLater() -> TabBarPage {
    XCTAssertTrue(deferButton.waitForExistence(timeout: 5), "Defer button should exist")
    tapAndEnsureNavigation(element: deferButton, expectedElement: app.textFields["Payload"])
    return TabBarPage(app: app)
  }
}
// swiftlint:enable prefer_nimble
