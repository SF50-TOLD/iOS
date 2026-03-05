import XCTest

extension XCUIElement {
  var isVisible: Bool {
    guard self.exists && !self.frame.isEmpty else { return false }
    let app = XCUIApplication()
    guard let firstWindow = app.windows.allElementsBoundByIndex.first else { return false }
    return firstWindow.frame.contains(self.frame)
  }

  func toggleOn() {
    guard switches["0"].exists else { return }
    switches["0"].firstMatch.tap()
  }

  func toggleOff() {
    guard switches["1"].exists else { return }
    switches["1"].firstMatch.tap()
  }

  func makeVisible(element: XCUIElement) -> XCUIElement? {
    if self.elementType == .scrollView || self.elementType == .collectionView
      || self.elementType == .table
    {
      let visible = self.scroll(to: element) || self.swipe(to: element)
      return visible ? element : nil
    }
    return self.swipe(to: element) ? element : nil
  }

  // Use the collection view's scrollToItem method via coordinate-based scrolling
  private func scroll(to element: XCUIElement) -> Bool {
    var attempts = 0

    while !element.isVisible && attempts < 10 {
      let startCoordinate = self.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
      let endCoordinate = self.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
      startCoordinate.press(forDuration: 0.01, thenDragTo: endCoordinate)
      attempts += 1
    }

    return element.isVisible
  }

  // Fallback to swipe-based scrolling with limits
  private func swipe(to element: XCUIElement) -> Bool {
    var attempts = 0

    while !element.isVisible && attempts < 10 {
      swipeUp()
      attempts += 1
    }

    return element.isVisible
  }
}

extension XCUIApplication {
  func scrollToTop() {
    // Tap status bar to scroll to top, falling back to coordinate tap
    let springboardApp = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    let statusBars = springboardApp.statusBars.allElementsBoundByIndex
    if statusBars.isEmpty {
      coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.02)).tap()
    } else {
      statusBars.first?.tap()
    }
  }

  /// Finds a tab button by label, checking both the standard tab bar (iPhone) and
  /// the floating tab bar (iPad) which doesn't expose a `TabBar` element.
  func tabButton(_ label: String) -> XCUIElement {
    let tabBarButton = tabBars.buttons[label]
    if tabBarButton.exists { return tabBarButton }
    return buttons[label].firstMatch
  }

  // Tap tab by label (works on both iPhone tab bar and iPad floating tabs)
  func tapTab(_ label: String) {
    tabButton(label).tap()
  }
}

// Helper function for clearing and typing text in fields
extension XCUIElement {
  func clearAndType(_ text: String, app: XCUIApplication) {
    // Dismiss keyboard popover on iPad if present
    if app.otherElements["PopoverDismissRegion"].exists {
      app.otherElements["PopoverDismissRegion"].tap()
    }

    // Tap and wait for keyboard to appear, retrying if needed
    for _ in 0..<3 {
      tap()
      if app.keyboards.firstMatch.waitForExistence(timeout: 2) { break }
    }

    // Triple tap to select all, then pause for selection to register
    tap(withNumberOfTaps: 3, numberOfTouches: 1)
    Thread.sleep(forTimeInterval: 0.3)

    // Type new text (will replace selection)
    typeText(text)
  }
}

// Helper to tap element and ensure navigation occurred
@MainActor
func tapAndEnsureNavigation(
  element: XCUIElement,
  expectedElement: XCUIElement,
  timeout: TimeInterval = 2
) {
  element.tap()

  // If expected element doesn't appear, tap again (needed on some devices)
  if !expectedElement.waitForExistence(timeout: timeout) {
    element.tap()
  }
}
