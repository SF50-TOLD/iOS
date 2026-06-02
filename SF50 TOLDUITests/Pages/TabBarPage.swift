import XCTest
import XCUITestKit

final class TabBarPage: BasePage {

  func goToTakeoff() -> TakeoffPage {
    if !app.tabButton("Takeoff").isSelected {
      app.tapTab("Takeoff")
    }
    return TakeoffPage(app: app)
  }

  func goToLanding() -> LandingPage {
    app.tapTab("Landing")
    return LandingPage(app: app)
  }

  func goToClimb() -> ClimbPage {
    app.tapTab("Climb")
    return ClimbPage(app: app)
  }

  func goToSettings() -> SettingsPage {
    app.tapTab("Settings")
    return SettingsPage(app: app)
  }

  func goToAbout() -> AboutPage {
    app.tapTab("About")
    return AboutPage(app: app)
  }
}
