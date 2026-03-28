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
    let toggle = switches["0"].firstMatch
    if toggle.isHittable {
      toggle.tap()
    } else {
      toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }
  }

  func toggleOff() {
    guard switches["1"].exists else { return }
    let toggle = switches["1"].firstMatch
    if toggle.isHittable {
      toggle.tap()
    } else {
      toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }
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

  // Tap tab by label (works on both iPhone tab bar and iPad floating tabs).
  // Falls back to coordinate-based tap for iOS 26 Liquid Glass overlay.
  func tapTab(_ label: String) {
    let button = tabButton(label)
    if button.isHittable {
      button.tap()
    } else {
      button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }
  }
}

// Helper function for clearing and typing text in fields
extension XCUIElement {
  func clearAndType(_ text: String, app: XCUIApplication) {
    // Dismiss keyboard popover on iPad if present
    if app.otherElements["PopoverDismissRegion"].exists {
      app.otherElements["PopoverDismissRegion"].tap()
    }

    // Tap and wait for keyboard to appear, retrying if needed.
    // Falls back to coordinate-based tap for iOS 26 Liquid Glass overlay.
    for _ in 0..<3 {
      if isHittable {
        tap()
      } else {
        coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
      }
      if app.keyboards.firstMatch.waitForExistence(timeout: 2) { break }
    }

    // Select all existing text so the new text replaces it.
    // On iPad with iOS 26 Liquid Glass, elements can become not-hittable
    // between keyboard focus and triple-tap. Nudge the content to restore
    // hittability so the direct triple-tap (which is the only reliable
    // select-all gesture) can succeed. If still not hittable, fall back to
    // dismissing the keyboard and retapping to reset layout state.
    if !isHittable {
      let collectionView = app.collectionViews.firstMatch
      if collectionView.exists {
        let windowHeight = app.windows.firstMatch.frame.height
        if frame.minY < windowHeight * 0.35 {
          let start = collectionView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
          let end = collectionView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
          start.press(forDuration: 0.01, thenDragTo: end)
        } else if frame.maxY > windowHeight * 0.70 {
          let start = collectionView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
          let end = collectionView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
          start.press(forDuration: 0.01, thenDragTo: end)
        }
      }
    }

    if isHittable {
      tap(withNumberOfTaps: 3, numberOfTouches: 1)
      Thread.sleep(forTimeInterval: 0.3)
      typeText(text)
    } else {
      // Field has keyboard focus but Liquid Glass prevents direct triple-tap.
      // Wait for keyboard/Liquid Glass animations to settle, then retry.
      // If still not hittable, dismiss keyboard and tap again to reset state.
      Thread.sleep(forTimeInterval: 0.5)
      if !isHittable {
        // Dismiss keyboard to reset layout, then retap
        app.swipeDown()
        Thread.sleep(forTimeInterval: 0.3)
        coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        if app.keyboards.firstMatch.waitForExistence(timeout: 2) {
          Thread.sleep(forTimeInterval: 0.3)
        }
      }
      // Last resort: attempt triple-tap even if not hittable (may work after reset)
      tap(withNumberOfTaps: 3, numberOfTouches: 1)
      Thread.sleep(forTimeInterval: 0.3)
      typeText(text)
    }
  }
}

// Helper to tap element and ensure navigation occurred.
// Falls back to coordinate-based tap for iOS 26 Liquid Glass overlay.
@MainActor
func tapAndEnsureNavigation(
  element: XCUIElement,
  expectedElement: XCUIElement,
  timeout: TimeInterval = 5
) {
  for _ in 0..<3 {
    if element.exists {
      if element.isHittable {
        element.tap()
      } else {
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
      }
    }
    if expectedElement.waitForExistence(timeout: timeout) { return }
  }
}
