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

    // SwiftUI `Toggle("Engine IPS", isOn:)` in a Form renders differently per
    // platform/iOS version. Cast a wide net so at least one strategy lands a
    // touch event that actually flips the switch.
    let label = app.staticTexts["Engine IPS"]
    let labelCell = app.cells.containing(.staticText, identifier: "Engine IPS").firstMatch
    let strategies: [() -> Void] = [
      // Tap a child .switch element — works on iOS 26 where the accessibility
      // ID is on a cell wrapping a switch widget
      { toggle!.switches.firstMatch.tap() },
      // Tap the row label — SwiftUI Form Toggle forwards row taps to the switch
      { if label.exists { label.tap() } },
      { if labelCell.exists { labelCell.tap() } },
      // Sweep tap coordinates across the toggle's frame (handles wide iPad rows)
      { toggle!.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap() },
      { toggle!.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)).tap() },
      { toggle!.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() },
      { toggle!.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5)).tap() },
      // iOS 18 Form cells have delaysContentTouches — a long press defeats it
      { toggle!.press(forDuration: 0.25) },
      {
        toggle!.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)).press(
          forDuration: 0.25
        )
      }
    ]

    for strategy in strategies {
      strategy()
      // Poll up to 1s for the value to flip; tap dispatch can be async on iPad
      let deadline = Date().addingTimeInterval(1.0)
      while Date() < deadline {
        if (toggle!.value as? String ?? "unknown") != valueBefore { return }
        Thread.sleep(forTimeInterval: 0.1)
      }
    }

    XCTFail(
      "Failed to toggle ice protection (value stayed \(valueBefore), frame=\(toggle!.frame))"
    )
  }
}
// swiftlint:enable prefer_nimble
