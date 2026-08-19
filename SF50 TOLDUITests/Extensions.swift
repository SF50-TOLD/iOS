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

  /// Waits for this element to become first responder, so that typing into it lands here rather
  /// than failing in a window with no keyboard focus.
  func waitForKeyboardFocus(timeout: TimeInterval = 5) -> Bool {
    let focused = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "hasKeyboardFocus == true"),
      object: self
    )
    return XCTWaiter().wait(for: [focused], timeout: ScaledTimeouts.scaled(timeout)) == .completed
  }
}

// MARK: - Navigation helpers

/// Tap `element` with escalating strategies until `expectedElement` appears,
/// handling Liquid Glass overlays and iPad layouts. `timeout` is the base
/// per-strategy wait in seconds; CI scaling is applied here.
func tapAndEnsureNavigation(
  element: XCUIElement,
  expectedElement: XCUIElement,
  timeout: TimeInterval = 5
) {
  element.tap(
    untilExists: expectedElement,
    using: XCUIElement.TapStrategy.escalating,
    timeout: ScaledTimeouts.scaled(timeout)
  )
}

extension XCUIApplication {
  /// Finds the airport list picker regardless of whether the platform renders
  /// it as a SegmentedControl (iPhone) or TabGroup (iPad on iOS 26).
  func airportListPicker() -> XCUIElement {
    let predicate = NSPredicate(format: "identifier == 'airportListPicker'")
    return descendants(matching: .any).matching(predicate).firstMatch
  }
}
