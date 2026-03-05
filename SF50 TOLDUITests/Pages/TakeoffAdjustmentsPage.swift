import XCTest

final class TakeoffAdjustmentsPage: BasePage {

  func hasGroundRunSection() -> Bool {
    app.staticTexts["Ground Run"].exists
  }

  func hasTotalDistanceSection() -> Bool {
    app.staticTexts["Total Distance"].exists
  }

  func goBack() {
    tapBackButton()
  }
}
