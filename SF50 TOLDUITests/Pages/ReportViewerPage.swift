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

  /// Whether the report itself rendered, rather than just the sheet around it.
  ///
  /// The navigation bar appears whether or not the web view drew anything, so this looks for a
  /// heading from inside the document.
  func showsReportContent() -> Bool {
    app.webViews.staticTexts["Available Runways"].waitForExistence(timeout: 15)
  }

  func dismiss() {
    let doneButton = app.buttons["Done"]
    XCTAssertTrue(doneButton.exists, "Done button should be present in report viewer")
    forceTap(doneButton)
  }
}
