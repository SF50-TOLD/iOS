import XCTest
import XCUITestKit

final class TabBarPage: BasePage {

  func goToTakeoff() -> TakeoffPage {
    switchToTab("Takeoff")
    return TakeoffPage(app: app)
  }

  func goToLanding() -> LandingPage {
    switchToTab("Landing")
    return LandingPage(app: app)
  }

  func goToClimb() -> ClimbPage {
    switchToTab("Climb")
    return ClimbPage(app: app)
  }

  func goToSettings() -> SettingsPage {
    switchToTab("Settings")
    return SettingsPage(app: app)
  }

  func goToAbout() -> AboutPage {
    switchToTab("About")
    return AboutPage(app: app)
  }

  /// Select a tab, retrying until it reports selected. On iOS 26 the first tap
  /// after a sheet or menu dismissal is absorbed by the dismissing overlay, so a
  /// single `tapTab` can silently leave the previous tab showing.
  private func switchToTab(_ name: String) {
    // A keyboard left up by the previous screen (e.g. the airport-picker search)
    // covers the tab bar, so every tap on the tab is swallowed; dismiss it first.
    if app.keyboards.firstMatch.exists {
      app.dismissKeyboardStable()
    }
    tapUntilSelected(app.tabButton(name))
  }
}
