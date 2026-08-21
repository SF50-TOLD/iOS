import XCTest
import XCUITestKit

final class NOTAMPage: BasePage {

  // MARK: - Elements

  var distanceField: XCUIElement { app.textFields["distanceField"] }
  var obstacleHeightField: XCUIElement { app.textFields["obstacleHeightField"] }
  var obstacleDistanceField: XCUIElement { app.textFields["obstacleDistanceField"] }
  var contaminationTypePicker: XCUIElement { app.buttons["contaminationTypePicker"] }
  var contaminationDepthSlider: XCUIElement { app.sliders["contaminationDepthSlider"] }

  // MARK: - Runway Shortening

  func setRunwayShortening(_ value: String) {
    XCTAssertTrue(distanceField.waitForExistence(timeout: 2), "Distance field should exist")
    distanceField.clearAndType(value, app: app, replacingSelection: true, verifying: true)
    dismissKeyboard()
  }

  // MARK: - Obstacle (Takeoff)

  func setObstacleHeight(_ value: String) {
    XCTAssertTrue(
      obstacleHeightField.waitForExistence(timeout: 2),
      "Obstacle height field should exist"
    )
    obstacleHeightField.clearAndType(value, app: app, replacingSelection: true, verifying: true)
  }

  func setObstacleDistance(_ value: String) {
    XCTAssertTrue(
      obstacleDistanceField.waitForExistence(timeout: 2),
      "Obstacle distance field should exist"
    )
    obstacleDistanceField.clearAndType(value, app: app, replacingSelection: true, verifying: true)
  }

  // MARK: - Contamination (Landing)

  func selectContamination(_ type: String) {
    if contaminationTypePicker.waitForExistence(timeout: 2) {
      ensureHittable(contaminationTypePicker)
      let option = app.buttons[type]
      // Opening the picker is a single tap that iPad/Liquid Glass can drop,
      // leaving the menu closed; escalate the tap until the option appears.
      let opened = contaminationTypePicker.tap(
        untilExists: option,
        using: XCUIElement.TapStrategy.escalating
      )
      XCTAssertTrue(
        opened,
        "Contamination option \"\(type)\" should appear after opening the picker"
      )
      forceTap(option)
    }
  }

  func adjustContaminationDepth(to normalizedPosition: CGFloat) {
    if contaminationDepthSlider.waitForExistence(timeout: 2) {
      contaminationDepthSlider.adjust(toNormalizedSliderPosition: normalizedPosition)
    }
  }

  // MARK: - Actions

  func clearAllNOTAMs() {
    let clearButton = app.buttons["clearNOTAMsButton"]
    XCTAssertTrue(clearButton.waitForExistence(timeout: 2), "Clear NOTAMs button should exist")
    ensureHittable(clearButton)
    forceTap(clearButton)
  }

  func goBack() {
    tapBackButton()
  }
}
