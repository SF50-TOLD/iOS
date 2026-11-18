import XCTest
import XCUITestKit

final class RunwayMapPage: BasePage {

  func isDisplayed(runway: String) -> Bool {
    app.navigationBars["Runway \(runway)"].wait(timeout: 5)
  }

  func goBack() {
    tapBackButton()
  }
}
