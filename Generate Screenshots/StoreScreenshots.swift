import XCTest
import XCUIPromoKit
import XCUITestKit

/// Captures the stills `promo/storyboard.json` sets as App Store screenshots. `promokit stills`
/// runs it; anywhere else, the test skips.
///
/// A G2 out of Aspen's runway 33 and back into runway 15: the aircraft setup, the takeoff's
/// weather, results and report, the climb along LINDZ1 over the terrain, then the landing's results
/// and its ground run on the map, and the enroute climb.
nonisolated final class StoreScreenshots: XCTestCase {
  private static let bannerDismissal: TimeInterval = 30,
    chartSettle: TimeInterval = 2.0,
    mapSettle: TimeInterval = 2.0

  @MainActor
  override func setUp() async throws {
    continueAfterFailure = false
    try XCTSkipUnless(
      ProcessInfo.processInfo.environment[PromoStill.directoryVariable] != nil,
      "Only `promokit stills` captures the App Store stills."
    )
  }
}

@MainActor
extension StoreScreenshots {

  func testCaptureStills() throws {
    let app = XCUIApplication()
    app.launchArguments = PromoLaunch(flags: XCUIApplication.captureLaunchArguments).arguments
    app.launch()

    // wait for the Apple Intelligence banner to self-dismiss
    Thread.sleep(forTimeInterval: Self.bannerDismissal)

    try app.completeWelcome { try capture(.aircraftSetup) }
    app.downloadNorthAmericaTerrain()

    app.tapTab("Takeoff")
    app.enterLoad(payload: "530", fuel: "212")
    app.selectAspen(runway: "33")
    try captureWeather(in: app)
    try captureResults(.takeoff, through: "vxClimbRateValue", in: app)
    try captureTakeoffReport(in: app)
    try captureClimbProfile(in: app)

    app.tapTab("Landing")
    app.enterLoad(payload: "530", fuel: "75")
    app.selectAspen(runway: "15")
    try captureResults(.landing, through: "goAroundClimbGradientValue", in: app)
    try captureLandingMap(in: app)

    app.tapTab("Climb")
    try capture(.enrouteClimb)
  }

  private func capture(_ shot: Shot) throws {
    try PromoStill.capture(shot.rawValue, in: self)
  }

  /// Opens the takeoff's weather from the top of the form, captures it, and goes back.
  private func captureWeather(in app: XCUIApplication) throws {
    app.scrollToTop()
    let weatherSelector = app.collectionViews.firstMatch.makeVisible(
      element: app.buttons["weatherSelector"]
    )
    XCTAssertNotNil(weatherSelector, "Weather selector should be reachable")

    // The Liquid Glass bar can swallow the tap that presents the picker.
    tapAndEnsureNavigation(
      element: weatherSelector!,
      expectedElement: app.textFields["windDirectionField"].firstMatch
    )
    try capture(.weather)
    app.goBack()
  }

  /// Scrolls the form until its last result is on screen, then captures it.
  ///
  /// - Parameters:
  ///   - shot: The still to capture.
  ///   - lastResult: The identifier of the result the performance section ends with.
  ///   - app: The app under test.
  private func captureResults(
    _ shot: Shot,
    through lastResult: String,
    in app: XCUIApplication
  ) throws {
    let result = app.collectionViews.firstMatch.makeVisible(element: app.staticTexts[lastResult])
    XCTAssertNotNil(result, "\(lastResult) should be reachable")
    try capture(shot)
  }

  /// Presents the takeoff report, captures it once its web view shows text, and dismisses it.
  private func captureTakeoffReport(in app: XCUIApplication) throws {
    let reportButton = app.collectionViews.firstMatch.makeVisible(
      element: app.buttons["generateTakeoffReportButton"]
    )
    XCTAssertNotNil(reportButton, "Generate takeoff report button should be reachable")
    tapAndEnsureNavigation(element: reportButton!, expectedElement: app.webViews.firstMatch)
    XCTAssertTrue(
      app.webViews.firstMatch.staticTexts.firstMatch.waitForExistence(timeout: 30),
      "Takeoff report should render"
    )
    try capture(.takeoffReport)

    // The report's web view swallows a swipe down, so the sheet is closed through its Done button.
    let doneButton = app.buttons["Done"].firstMatch
    if doneButton.waitForExistence(timeout: 5) { doneButton.forceTap() }
    XCTAssertTrue(
      app.webViews.firstMatch.waitForNonExistence(timeout: 10),
      "Takeoff report should close"
    )
  }

  /// Opens the climb profile on the LINDZ departure with its weather layers, and captures it.
  private func captureClimbProfile(in app: XCUIApplication) throws {
    let showClimb = app.collectionViews.firstMatch.makeVisible(
      element: app.buttons["showClimbProfileButton"]
    )
    XCTAssertNotNil(showClimb, "Show Climb should be reachable")

    // The link sits just above the tab bar and ignores a plain synthesized tap.
    tapAndEnsureNavigation(
      element: showClimb!,
      expectedElement: app.navigationBars["Climb Profile"]
    )

    app.selectLINDZDeparture()
    let chart = app.descendants(matching: .any)["terrainProfileChart"].firstMatch
    XCTAssertTrue(chart.waitForExistence(timeout: 30), "Terrain chart should appear")
    app.showWeatherLayers()
    app.scrollIntoFullView(chart)
    Thread.sleep(forTimeInterval: Self.chartSettle)

    try capture(.climbProfile)
    app.goBack()
  }

  /// Shows the landing's ground run on a satellite map of the runway, captures it, and goes back.
  private func captureLandingMap(in app: XCUIApplication) throws {
    let showMap = app.collectionViews.firstMatch.makeVisible(
      element: app.buttons["showLandingMapButton"]
    )
    XCTAssertNotNil(showMap, "Show landing map should be reachable")
    XCTAssertTrue(showMap!.isEnabled, "Runway 15 should have threshold coordinates to map")
    showMap!.forceTap()
    Thread.sleep(forTimeInterval: Self.mapSettle)

    try capture(.landingMap)
    app.goBack()
  }

  /// The stills `promo/storyboard.json` captions.
  private enum Shot: String {
    case aircraftSetup = "aircraft-setup"
    case weather
    case takeoff
    case takeoffReport = "takeoff-report"
    case climbProfile = "climb-profile"
    case landing
    case landingMap = "landing-map"
    case enrouteClimb = "enroute-climb"
  }
}
