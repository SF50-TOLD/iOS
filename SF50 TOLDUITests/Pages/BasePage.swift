import XCTest
import XCUITestKit

class BasePage {
  let app: XCUIApplication

  init(app: XCUIApplication) {
    self.app = app
  }

  /// Tap an element, falling back to coordinate-based tap when not hittable.
  /// Works around iOS 26 Liquid Glass overlay making elements "not hittable".
  func forceTap(_ element: XCUIElement) {
    element.forceTap()
  }

  /// Nudge content so an element sits clear of the iOS 26 Liquid Glass bars,
  /// whose translucent nav/tab bars report an underlapping element as
  /// `isHittable` yet swallow taps that land on them.
  func ensureHittable(_ element: XCUIElement) {
    app.scrollIntoSafeBand(element)
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
    if element.waitForExistence(timeout: 5) && element.isVisible {
      ensureHittable(element)
      return element
    }

    // Scroll to find the element. On smaller screens (e.g. iPhone SE) lazy list
    // cells may not exist in the hierarchy until scrolled. On iPad,
    // `collectionViews.firstMatch` can resolve to the wrong scroll container
    // (e.g. the floating tab bar), and the target may sit *above* the current
    // viewport, so scroll every collection view in both directions.
    let containers = app.collectionViews
    let containerCount = max(containers.count, 1)

    for index in 0..<containerCount {
      let container =
        containerCount == 1 ? containers.firstMatch : containers.element(boundBy: index)
      guard container.exists else { continue }

      // Scroll down (swipe up), then up (swipe down), so an element on either
      // side of the current position is reached.
      for direction in [(from: 0.8, to: 0.2), (from: 0.2, to: 0.8)] {
        for _ in 0..<12 {
          if element.waitForExistence(timeout: 0.3) && element.isVisible {
            ensureHittable(element)
            return element
          }
          let start = container.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: direction.from)
          )
          let end = container.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: direction.to)
          )
          start.press(forDuration: 0.01, thenDragTo: end)
        }
      }

      if element.exists, element.isVisible {
        ensureHittable(element)
        return element
      }
    }

    if element.exists {
      ensureHittable(element)
      return element
    }
    return nil
  }

  func tapBackButton() {
    let button = app.navigationBars.buttons.element(boundBy: 0)
    _ = button.waitUntilHittable()
    forceTap(button)
  }

  /// Tap an element until it reports selected, retrying a dropped tap. On iOS 26
  /// the first tap on a Liquid Glass segmented control or tab bar can be absorbed
  /// by an animating overlay, silently leaving the previous selection in place.
  func tapUntilSelected(_ element: XCUIElement, attempts: Int = 6) {
    for _ in 0..<attempts {
      if element.isSelected { return }
      forceTap(element)
      _ = XCTWaiter().wait(
        for: [
          XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isSelected == true"),
            object: element
          )
        ],
        timeout: 2
      )
    }
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

  /// Polls an element's label until it contains the expected text, then returns the label.
  func waitForLabel(
    of element: XCUIElement,
    toContain text: String,
    timeout: TimeInterval = 10
  ) -> String {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      let label = scrollToElement(element)?.label ?? ""
      if label.contains(text) { return label }
      Thread.sleep(forTimeInterval: 0.2)
    }
    return scrollToElement(element)?.label ?? ""
  }

  func clearAndType(_ element: XCUIElement, _ text: String) {
    element.clearAndType(text, app: app)
  }

  func dismissKeyboard() {
    if app.keyboards.count > 0 {  // swiftlint:disable:this empty_count
      let navBar = app.navigationBars.firstMatch
      forceTap(navBar)
    }
  }
}
