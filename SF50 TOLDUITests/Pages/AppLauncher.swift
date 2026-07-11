import XCTest
import XCUITestKit

enum WeatherMode: String {
  case ISA = "WEATHER-ISA"
  case NWS = "WEATHER-NWS"
  case error = "WEATHER-ERROR"
}

struct AppLauncher {
  var weatherMode: WeatherMode = .ISA
  var useRegressionModel: Bool = false
  var skipScenarioSeeding: Bool = false
  var staleNavData: Bool = false
  var favoriteAirportIDs: [String] = []

  @MainActor
  func launch() -> WelcomePage {
    let app = XCUIApplication()
    var args = [
      "UI-TESTING",
      weatherMode.rawValue,
      "-AppleKeyboardAutocorrection", "NO",
      "-AppleKeyboardPrediction", "NO"
    ]
    if useRegressionModel {
      args.append("USE-REGRESSION-MODEL")
    }
    if skipScenarioSeeding {
      args.append("SKIP-SCENARIO-SEEDING")
    }
    if staleNavData {
      args.append("STALE-NAV-DATA")
    }
    if !favoriteAirportIDs.isEmpty {
      args.append("FAVORITE-AIRPORTS=\(favoriteAirportIDs.joined(separator: ","))")
    }
    app.launchArguments = args
    app.disableLogStderrMirroring()
    app.launch()

    // Wait for the app to be ready before interacting
    _ = app.wait(for: .runningForeground, timeout: 10)

    return WelcomePage(app: app)
  }

  @MainActor
  func launchAndCompleteSetup(
    emptyWeight: String,
    model: String = "G1"
  ) -> TabBarPage {
    let welcome = launch()
    welcome.handleDatabaseLoaderIfNeeded()
    welcome.waitForReady()
    welcome.selectModel(model)
    welcome.setEmptyWeight(emptyWeight)
    return welcome.tapContinue()
  }
}
