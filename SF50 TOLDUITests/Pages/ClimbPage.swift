// swiftlint:disable prefer_nimble
import XCTest

final class ClimbPage: BasePage {

  // MARK: - Elements

  var fuelSlider: XCUIElement { app.sliders["climbFuelSlider"] }
  var altitudeSlider: XCUIElement { app.sliders["climbAltitudeSlider"] }
  var ISADeviationSlider: XCUIElement { app.sliders["climbISADeviationSlider"] }
  var iceProtectionToggle: XCUIElement { app.switches["climbIceProtectionToggle"] }

  // MARK: - Results

  var speedValue: XCUIElement { app.staticTexts["climbSpeedValue"] }
  var rateValue: XCUIElement { app.staticTexts["climbRateValue"] }
  var gradientValue: XCUIElement { app.staticTexts["climbGradientValue"] }

  var speedLabel: String { speedValue.label }
  var rateLabel: String { rateValue.label }
  var gradientLabel: String { gradientValue.label }

  // MARK: - Actions

  func adjustFuel(to normalizedPosition: CGFloat) {
    XCTAssertTrue(fuelSlider.waitForExistence(timeout: 2), "Fuel slider should exist")
    fuelSlider.adjust(toNormalizedSliderPosition: normalizedPosition)
  }

  func adjustAltitude(to normalizedPosition: CGFloat) {
    XCTAssertTrue(altitudeSlider.exists, "Altitude slider should exist")
    altitudeSlider.adjust(toNormalizedSliderPosition: normalizedPosition)
  }

  func adjustISADeviation(to normalizedPosition: CGFloat) {
    XCTAssertTrue(ISADeviationSlider.exists, "ISA Deviation slider should exist")
    ISADeviationSlider.adjust(toNormalizedSliderPosition: normalizedPosition)
  }

  func toggleIceProtection() {
    let toggle = scrollToElement(iceProtectionToggle)
    XCTAssertNotNil(toggle, "Ice Protection toggle should exist")
    ensureHittable(toggle!)

    let valueBefore = toggle!.value as? String ?? "unknown"

    // SwiftUI Toggle inside a Form: the row is the switch. Tap positions vary
    // by iOS version because of Liquid Glass insets. Sweep a set of tap
    // targets and confirm the switch value flips after each.
    // - center/right of switch knob (iPhone iOS 26)
    // - 0.85 dx coordinate (iPad iOS 18.4 knob position)
    // - left-of-knob (iPad iOS 26 Liquid Glass slide gesture)
    // - long-press (iOS 18 Form delaysContentTouches)
    let strategies: [(XCUIElement) -> Void] = [
      { $0.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() },
      { $0.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)).tap() },
      { $0.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5)).tap() },
      { $0.tapStable() },
      { $0.press(forDuration: 0.25) },
      { $0.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)).press(forDuration: 0.25) }
    ]

    for strategy in strategies {
      strategy(toggle!)
      // Poll up to 1s for the value to flip; tap dispatch can be async on iPad
      let deadline = Date().addingTimeInterval(1.0)
      while Date() < deadline {
        if (toggle!.value as? String ?? "unknown") != valueBefore { return }
        Thread.sleep(forTimeInterval: 0.1)
      }
    }

    XCTFail(
      "Failed to toggle ice protection (value stayed \(valueBefore))"
    )
  }
}
// swiftlint:enable prefer_nimble
