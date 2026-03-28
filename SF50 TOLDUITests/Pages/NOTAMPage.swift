// swiftlint:disable prefer_nimble
import XCTest

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
    distanceField.clearAndType(value, app: app)
    dismissKeyboard()
  }

  // MARK: - Obstacle (Takeoff)

  func setObstacleHeight(_ value: String) {
    XCTAssertTrue(
      obstacleHeightField.waitForExistence(timeout: 2),
      "Obstacle height field should exist"
    )
    obstacleHeightField.clearAndType(value, app: app)
  }

  func setObstacleDistance(_ value: String) {
    XCTAssertTrue(
      obstacleDistanceField.waitForExistence(timeout: 2),
      "Obstacle distance field should exist"
    )
    obstacleDistanceField.clearAndType(value, app: app)
  }

  // MARK: - Contamination (Landing)

  func selectContamination(_ type: String) {
    if contaminationTypePicker.waitForExistence(timeout: 2) {
      ensureHittable(contaminationTypePicker)
      forceTap(contaminationTypePicker)
      let option = app.buttons[type]
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
    XCTAssertTrue(clearButton.exists, "Clear NOTAMs button should exist")
    ensureHittable(clearButton)
    forceTap(clearButton)
  }

  func goBack() {
    tapBackButton()
  }
}
// swiftlint:enable prefer_nimble
