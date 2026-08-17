import XCTest

/// What the climb and go-around profile screens share: the same chart, plotted from the same
/// pipeline, behind the same weather controls.
class ProfilePage: BasePage {

  func isChartVisible(timeout: TimeInterval = 30) -> Bool {
    let chart = app.descendants(matching: .any)["terrainProfileChart"]
    return chart.waitForExistence(timeout: timeout)
  }

  /// Opens one of the chart's weather pull-downs.
  ///
  /// - Parameter identifier: The pill's accessibility identifier.
  /// - Returns: Whether the pill was found and tapped.
  @discardableResult
  func openWeatherMenu(_ identifier: String) -> Bool {
    guard let pill = scrollToElement(app.descendants(matching: .any)[identifier]) else {
      XCTFail("“\(identifier)” not found")
      return false
    }
    forceTap(pill)
    return true
  }

  func goBack() {
    tapBackButton()
  }
}
