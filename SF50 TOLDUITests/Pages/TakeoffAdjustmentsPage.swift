import XCTest
import XCUITestKit

final class TakeoffAdjustmentsPage: BasePage {

  func hasGroundRunSection() -> Bool {
    app.staticTexts["Ground Run"].wait()
  }

  func hasTotalDistanceSection() -> Bool {
    app.staticTexts["Total Distance"].wait()
  }

  func goBack() {
    tapBackButton()
  }
}
