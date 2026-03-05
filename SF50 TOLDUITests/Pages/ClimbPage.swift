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
    let valueBefore = toggle!.value as? String
    toggle!.tap()

    // Verify the toggle actually changed; retry with coordinate tap if needed
    let valueAfter = toggle!.value as? String
    if valueAfter == valueBefore {
      toggle!.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
    }
  }
}
// swiftlint:enable prefer_nimble
