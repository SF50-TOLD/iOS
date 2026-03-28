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

    // Try multiple tap strategies to handle platform differences:
    // - iOS 18 Form cells have delaysContentTouches, requiring longer presses
    // - iOS 26 iPad Liquid Glass can intercept taps at certain positions
    let strategies: [(XCUIElement) -> Void] = [
      { $0.switches.firstMatch.tap() },
      { $0.press(forDuration: 0.2) },
      { $0.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)).press(forDuration: 0.2) },
      { $0.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)).tap() }
    ]

    for strategy in strategies {
      strategy(toggle!)
      Thread.sleep(forTimeInterval: 0.5)
      if (toggle!.value as? String ?? "unknown") != valueBefore { return }
    }

    XCTFail(
      "Failed to toggle ice protection (value stayed \(valueBefore))"
    )
  }
}
// swiftlint:enable prefer_nimble
