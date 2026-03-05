import XCTest

final class AboutPage: BasePage {

  func hasAircraftDescription() -> Bool {
    app.staticTexts.matching(
      NSPredicate(format: "label CONTAINS 'Cirrus SF50 Vision'")
    ).firstMatch.exists
  }

  func hasNASRCycleLabel() -> Bool {
    app.staticTexts.matching(
      NSPredicate(format: "label CONTAINS 'NASR Cycle'")
    ).firstMatch.exists
  }

  func hasFAADisclaimer() -> Bool {
    let disclaimer = app.descendants(matching: .any).matching(
      NSPredicate(format: "label CONTAINS 'not been approved by the FAA'")
    ).firstMatch
    if !disclaimer.exists {
      var scrollAttempts = 0
      while !disclaimer.exists && scrollAttempts < 10 {
        app.swipeUp()
        scrollAttempts += 1
      }
    }
    return disclaimer.waitForExistence(timeout: 2)
  }
}
