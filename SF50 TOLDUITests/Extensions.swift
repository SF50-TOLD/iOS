// swiftlint:disable prefer_nimble
import XCTest

/// Centralized timeouts for UI tests. CI sets a multiplier via the
/// `SF50_UI_TEST_TIMEOUT_MULTIPLIER` env var in the test plan; local runs
/// default to 1.0.
enum UITestTimeouts {
  static let multiplier: TimeInterval = {
    ProcessInfo.processInfo.environment["SF50_UI_TEST_TIMEOUT_MULTIPLIER"]
      .flatMap(TimeInterval.init) ?? 1
  }()

  static var element: TimeInterval { 5 * multiplier }
  static var launch: TimeInterval { 30 * multiplier }
  static var slowElement: TimeInterval { 15 * multiplier }
}

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

  private func swipe(to element: XCUIElement) -> Bool {
    var attempts = 0
    while !element.isVisible && attempts < 10 {
      swipeUp()
      attempts += 1
    }
    return element.isVisible
  }
}

// MARK: - Wait helpers

extension XCUIElement {
  /// Waits for the element to exist within the project-wide default timeout.
  @discardableResult
  func wait() -> Bool {
    waitForExistence(timeout: UITestTimeouts.element)
  }

  /// Short-window probe scaled by the timeout multiplier. Pass the *base*
  /// seconds; the multiplier is applied automatically.
  @discardableResult
  func wait(scaled seconds: TimeInterval) -> Bool {
    waitForExistence(timeout: seconds * UITestTimeouts.multiplier)
  }

  /// Waits for the element to satisfy a predicate within the default timeout.
  @discardableResult
  func waitFor(_ predicate: NSPredicate) -> Bool {
    let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
    return
      XCTWaiter().wait(for: [expectation], timeout: UITestTimeouts.element) == .completed
  }
}

// MARK: - Stable tap

extension XCUIElement {
  /// Tap that waits for frame stability, then taps via center-coordinate. Use
  /// after `scrollToElement` for buttons/switches whose frame can briefly
  /// invalidate during SwiftUI relayout. Sidesteps "Activation point invalid"
  /// errors that plague iPad SwiftUI Form/List cells.
  func tapStable(file: StaticString = #filePath, line: UInt = #line) {
    waitForStableFrame(requireHittable: true, file: file, line: line)
    coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
  }

  /// Coordinate-tap variant that waits only for frame stability — does NOT
  /// require `isHittable`. For SwiftUI .pickerStyle(.navigationLink) cells
  /// whose underlying Button reports not-hittable even after the frame
  /// stabilizes.
  func coordinateTapWhenFrameStable(file: StaticString = #filePath, line: UInt = #line) {
    waitForStableFrame(requireHittable: false, file: file, line: line)
    coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
  }

  private func waitForStableFrame(
    requireHittable: Bool,
    file: StaticString,
    line: UInt
  ) {
    let deadline = Date().addingTimeInterval(UITestTimeouts.element)
    var lastFrame: CGRect = .null
    var stableHits = 0
    while Date() < deadline {
      let frameOK = frame.width > 0 && frame.height > 0
      let hittableOK = !requireHittable || isHittable
      if !frameOK || !hittableOK {
        Thread.sleep(forTimeInterval: 0.1)
        continue
      }
      if frame == lastFrame {
        stableHits += 1
        if stableHits >= 2 { break }
      } else {
        stableHits = 0
        lastFrame = frame
      }
      Thread.sleep(forTimeInterval: 0.1)
    }
    let hittableOK = !requireHittable || isHittable
    XCTAssertTrue(
      hittableOK && frame.width > 0 && frame.height > 0,
      "Element not stable for tap (frame=\(frame), hittable=\(isHittable))",
      file: file,
      line: line
    )
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

  /// Resigns first responder, then waits for the keyboard window to leave the
  /// hierarchy. Prefers tapping a navbar element to dismiss; falls back to a
  /// gentle upward swipe (SwiftUI Form auto-dismisses keyboard on scroll).
  func dismissKeyboardStable() {
    let keyboard = keyboards.firstMatch
    guard keyboard.exists else { return }

    let navBar = navigationBars.firstMatch
    if navBar.exists, navBar.isHittable {
      navBar.tap()
      if keyboard.waitForNonExistence(timeout: UITestTimeouts.element) { return }
    }

    let deadline = Date().addingTimeInterval(UITestTimeouts.element)
    while keyboard.exists && Date() < deadline {
      let start = coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
      let end = coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15))
      start.press(forDuration: 0.05, thenDragTo: end)
      _ = keyboard.waitForNonExistence(timeout: 1)
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

    // Select all existing text. On iPhone, triple-tap works natively. On
    // iPad with iOS 26 Liquid Glass overlays, the element can report "not
    // hittable" and the XCUIElement triple-tap fails, so fall back to
    // hardware-keyboard-emulated Cmd+A which bypasses hit-testing.
    if isHittable {
      tap(withNumberOfTaps: 3, numberOfTouches: 1)
    } else {
      typeKey("a", modifierFlags: .command)
    }
    Thread.sleep(forTimeInterval: 0.3)
    typeText(text)
  }
}

// Helper to tap element and ensure navigation occurred.
// Tries multiple strategies to handle Liquid Glass overlays and iPad layouts.
@MainActor
func tapAndEnsureNavigation(
  element: XCUIElement,
  expectedElement: XCUIElement,
  timeout: TimeInterval = 5
) {
  let strategies: [(XCUIElement) -> Void] = [
    {
      if $0.isHittable {
        $0.tap()
      } else {
        $0.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
      }
    },
    { $0.press(forDuration: 0.3) },
    { $0.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5)).press(forDuration: 0.3) }
  ]

  for strategy in strategies {
    guard element.exists else { return }
    strategy(element)
    if expectedElement.waitForExistence(timeout: timeout * UITestTimeouts.multiplier) { return }
  }
}

extension XCUIApplication {
  /// Finds the airport list picker regardless of whether the platform renders
  /// it as a SegmentedControl (iPhone) or TabGroup (iPad on iOS 26).
  func airportListPicker() -> XCUIElement {
    let predicate = NSPredicate(format: "identifier == 'airportListPicker'")
    return descendants(matching: .any).matching(predicate).firstMatch
  }
}
// swiftlint:enable prefer_nimble
