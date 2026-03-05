import XCTest

final class TerrainSettingsPage: BasePage {

  func isTotalDownloadedVisible() -> Bool {
    let totalDownloaded = app.descendants(matching: .any).matching(
      NSPredicate(format: "label CONTAINS 'Total Downloaded'")
    ).firstMatch
    if !totalDownloaded.exists {
      var scrollAttempts = 0
      while !totalDownloaded.exists && scrollAttempts < 10 {
        app.swipeUp()
        scrollAttempts += 1
      }
    }
    return totalDownloaded.waitForExistence(timeout: 2)
  }

  func goBack() {
    tapBackButton()
  }
}
