import XCTest

final class GoAroundProfilePage: ProfilePage {

  /// Whether a weather field can be chosen at all.
  ///
  /// Every field is drawn from the downloaded atmosphere, so with none to draw from the pill itself
  /// goes dead rather than opening onto options none of which can be picked.
  func isWeatherPillEnabled(timeout: TimeInterval = 10) -> Bool {
    let pill = app.descendants(matching: .any)["weatherLayerPicker"].firstMatch
    guard pill.waitForExistence(timeout: timeout) else {
      XCTFail("The weather pill was not found")
      return false
    }
    return pill.isEnabled
  }
}
