import XCTest
import XCUITestKit

@MainActor
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

  /// Nudge content to make an element hittable.
  /// Handles iOS 26 Liquid Glass nav bar/tab bar overlaying elements.
  func ensureHittable(_ element: XCUIElement) {
    guard element.exists, !element.isHittable else { return }
    let collectionView = app.collectionViews.firstMatch
    guard collectionView.exists else { return }
    let windowHeight = app.windows.firstMatch.frame.height

    for _ in 0..<5 {
      if element.frame.minY < windowHeight * 0.35 {
        let start = collectionView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
        let end = collectionView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.01, thenDragTo: end)
      } else if element.frame.maxY > windowHeight * 0.70 {
        let start = collectionView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
        let end = collectionView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
        start.press(forDuration: 0.01, thenDragTo: end)
      } else {
        break
      }
      if element.isHittable || !element.exists { return }
    }
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
    forceTap(button)
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

  /// Polls until the element exists and is hittable, then returns whether it is.
  ///
  /// Use for elements presented behind an animation (menu/picker options),
  /// whose frame is briefly invalid before presentation settles — tapping
  /// during that window fails with "Activation point invalid".
  @discardableResult
  func waitForHittable(_ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if element.exists, element.isHittable { return true }
      Thread.sleep(forTimeInterval: 0.2)
    }
    return element.exists && element.isHittable
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
