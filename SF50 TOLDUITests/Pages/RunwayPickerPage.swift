import XCTest
import XCUITestKit

final class RunwayPickerPage: BasePage {

  func selectRunway(_ runway: String) {
    let row = app.buttons["runwayRow-\(runway)"].firstMatch
    XCTAssertTrue(
      row.wait(timeout: 2),
      "Runway \(runway) should appear"
    )
    forceTap(row)
  }

  func isRunwayVisible(_ runway: String) -> Bool {
    app.buttons["runwayRow-\(runway)"].firstMatch.exists
  }

  func runwayRowLabel(_ runway: String) -> String {
    let row = app.buttons["runwayRow-\(runway)"].firstMatch
    return row.label
  }
}
