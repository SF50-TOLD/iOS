import XCTest

final class GoAroundProfilePage: BasePage {

  func isChartVisible(timeout: TimeInterval = 30) -> Bool {
    let chart = app.descendants(matching: .any)["terrainProfileChart"]
    return chart.waitForExistence(timeout: timeout)
  }

  func goBack() {
    tapBackButton()
  }
}
