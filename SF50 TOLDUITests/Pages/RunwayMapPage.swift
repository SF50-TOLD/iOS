import XCTest

final class RunwayMapPage: BasePage {

  func isDisplayed(runway: String) -> Bool {
    app.navigationBars["Runway \(runway)"].waitForExistence(timeout: 5)
  }

  func goBack() {
    tapBackButton()
  }
}
