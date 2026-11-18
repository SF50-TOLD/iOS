import XCTest
import XCUITestKit

final class LoadingConsentPage: BasePage {

  var downloadButton: XCUIElement { app.buttons["downloadDataButton"] }
  var deferButton: XCUIElement { app.buttons["deferDataButton"] }

  func isDisplayed() -> Bool {
    downloadButton.wait(timeout: 5)
  }

  func deferUntilLater() -> TabBarPage {
    XCTAssertTrue(deferButton.wait(timeout: 5), "Defer button should exist")
    tapAndEnsureNavigation(
      element: deferButton,
      expectedElement: app.textFields["payloadField"].firstMatch
    )
    return TabBarPage(app: app)
  }
}
