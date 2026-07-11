import XCTest

final class ReportViewerPage: BasePage {

  private let title: String

  init(app: XCUIApplication, title: String) {
    self.title = title
    super.init(app: app)
  }

  func isDisplayed() -> Bool {
    app.navigationBars[title].waitForExistence(timeout: 10)
  }

  func dismiss() {
    let doneButton = app.buttons["Done"]
    XCTAssertTrue(doneButton.exists, "Done button should be present in report viewer")
    forceTap(doneButton)
  }
}
