// swiftlint:disable prefer_nimble
import XCTest

final class RunwayPickerPage: BasePage {

  func selectRunway(_ runway: String) {
    let row = app.buttons["runwayRow-\(runway)"].firstMatch
    XCTAssertTrue(
      row.waitForExistence(timeout: 2),
      "Runway \(runway) should appear"
    )
    row.tap()
  }

  func isRunwayVisible(_ runway: String) -> Bool {
    app.buttons["runwayRow-\(runway)"].firstMatch.exists
  }

  func runwayRowLabel(_ runway: String) -> String {
    let row = app.buttons["runwayRow-\(runway)"].firstMatch
    return row.label
  }
}
// swiftlint:enable prefer_nimble
