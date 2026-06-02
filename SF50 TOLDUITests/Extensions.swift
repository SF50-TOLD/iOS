import XCTest
import XCUITestKit

extension XCUIElement {
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
}

// MARK: - Clear and type

@MainActor
extension XCUIElement {
  /// Clears a field completely, types `text`, then commits the value.
  ///
  /// Routes its primitives through XCUITestKit (``forceTap()``, ``ScaledTimeouts``,
  /// ``XCUIApplication/dismissKeyboardStable()``) but keeps SF50's hard-won iPad
  /// fix rather than calling XCUITestKit's ``clearAndType(_:app:)`` directly:
  ///
  /// 1. **Clears completely, verifying by reading back the value.** Triple-tap
  ///    select-all + overwrite is unreliable on iPad iOS 26 — the selection
  ///    often doesn't take, so new text is *prepended* to the old (e.g. typing
  ///    "4550" into a field holding "3550" yields "45503550", a 45-million-lb
  ///    aircraft, making every result offscale). XCUITestKit's `clearAndType`
  ///    deletes once based on the value's length without re-reading; this loops
  ///    until the field reads empty. An empty field reports its placeholder as
  ///    `value`, so `value == placeholderValue` (or empty) counts as clear —
  ///    correct for both numeric and plain string fields.
  /// 2. **Commits the value.** `TextField(value:format:)` only writes to its
  ///    binding when editing ends; on iPad iOS 26 typed text otherwise stays
  ///    uncommitted (default/offscale performance), and the `.decimalPad`
  ///    keyboard has no Return key. ``XCUIApplication/dismissKeyboardStable()``
  ///    resigns first responder and waits for the keyboard window to leave —
  ///    a no-op on screens without a keyboard (e.g. Welcome).
  func clearAndType(_ text: String, app: XCUIApplication) {
    if app.otherElements["PopoverDismissRegion"].exists {
      app.otherElements["PopoverDismissRegion"].tap()
    }

    // Tap and wait for keyboard to appear, retrying if needed.
    for _ in 0..<3 {
      forceTap()
      if app.keyboards.firstMatch.waitForExistence(timeout: ScaledTimeouts.scaled(2)) { break }
    }

    let placeholder = placeholderValue ?? ""
    for _ in 0..<5 {
      let current = (value as? String) ?? ""
      guard !current.isEmpty, current != placeholder else { break }
      if isHittable {
        tap(withNumberOfTaps: 3, numberOfTouches: 1)
      } else {
        typeKey("a", modifierFlags: .command)
      }
      Thread.sleep(forTimeInterval: 0.2)
      typeText(
        String(repeating: XCUIKeyboardKey.delete.rawValue, count: max(current.count, 1))
      )
      Thread.sleep(forTimeInterval: 0.2)
    }
    typeText(text)

    // Commit the value: `TextField(value:format:)` writes its binding only when
    // editing ends, and `.decimalPad` has no Return key. A plain nav-bar tap
    // resigns first responder without scrolling — unlike `dismissKeyboardStable`,
    // whose swipe fallback scrolls the settings List and hides later controls on
    // iPad. Guarded on `navBar.exists` so keyboard-less screens are unaffected.
    let navBar = app.navigationBars.firstMatch
    if navBar.exists { navBar.tap() }
  }
}

// MARK: - Navigation helpers

/// Helper to tap element and ensure navigation occurred.
/// Tries multiple strategies to handle Liquid Glass overlays and iPad layouts.
@MainActor
func tapAndEnsureNavigation(
  element: XCUIElement,
  expectedElement: XCUIElement,
  timeout: TimeInterval = 5
) {
  let strategies: [(XCUIElement) -> Void] = [
    { $0.forceTap() },
    { $0.press(forDuration: 0.3) },
    { $0.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5)).press(forDuration: 0.3) }
  ]

  for strategy in strategies {
    guard element.exists else { return }
    strategy(element)
    if expectedElement.waitForExistence(timeout: ScaledTimeouts.scaled(timeout)) { return }
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
