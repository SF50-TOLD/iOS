import XCTest

final class ClimbProfilePage: ProfilePage {

  /// Picks a weather field to draw behind the profile.
  ///
  /// - Parameter layer: The field's menu label, e.g. `"Temperature"`.
  func selectWeatherLayer(_ layer: String) {
    guard openWeatherMenu("weatherLayerPicker") else { return }

    let option = app.buttons[layer].firstMatch
    XCTAssertTrue(option.waitForExistence(timeout: 5), "“\(layer)” should be offered")
    forceTap(option)
  }

  /// Turns the along-track wind barbs on or off.
  func setWindBarbs(_ isOn: Bool) {
    guard openWeatherMenu("windBarbsPicker") else { return }

    let segment = isOn ? "On" : "Off"
    let option = app.buttons[segment].firstMatch
    XCTAssertTrue(option.waitForExistence(timeout: 5), "“\(segment)” should be offered")
    forceTap(option)
  }
}
