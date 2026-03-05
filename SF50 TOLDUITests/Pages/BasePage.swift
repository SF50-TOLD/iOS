import XCTest

@MainActor
class BasePage {
  let app: XCUIApplication

  init(app: XCUIApplication) {
    self.app = app
  }

  func extractNumericValue(from text: String) -> Double? {
    let cleanedText = text.replacingOccurrences(of: ",", with: "")
    let pattern = #"(\d+(?:\.\d+)?)"#
    guard let regex = try? NSRegularExpression(pattern: pattern),
      let match = regex.firstMatch(
        in: cleanedText,
        range: NSRange(cleanedText.startIndex..., in: cleanedText)
      ),
      let range = Range(match.range(at: 1), in: cleanedText)
    else {
      return nil
    }
    return Double(cleanedText[range])
  }

  @discardableResult
  func scrollToElement(_ element: XCUIElement) -> XCUIElement? {
    // If already visible, return immediately
    if element.waitForExistence(timeout: 5) && element.isVisible { return element }

    // Scroll the collection view to find the element. On smaller screens (e.g.
    // iPhone SE), lazy list cells may not exist in the hierarchy until scrolled.
    let collectionView = app.collectionViews.firstMatch
    guard collectionView.exists else { return nil }

    for _ in 0..<12 {
      let start = collectionView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
      let end = collectionView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
      start.press(forDuration: 0.01, thenDragTo: end)
      if element.waitForExistence(timeout: 0.3) && element.isVisible { return element }
    }

    return element.exists ? element : nil
  }

  func tapBackButton() {
    app.navigationBars.buttons.element(boundBy: 0).tap()
  }

  /// Polls an element's label until it differs from the given value, then returns the new label.
  func waitForLabelChange(
    _ element: XCUIElement,
    from previousLabel: String,
    timeout: TimeInterval = 3
  ) -> String {
    let deadline = Date().addingTimeInterval(timeout)
    while element.label == previousLabel && Date() < deadline {
      Thread.sleep(forTimeInterval: 0.2)
    }
    return element.label
  }

  func clearAndType(_ element: XCUIElement, _ text: String) {
    element.clearAndType(text, app: app)
  }

  func dismissKeyboard() {
    if app.keyboards.count > 0 {  // swiftlint:disable:this empty_count
      app.navigationBars.firstMatch.tap()
    }
  }
}
