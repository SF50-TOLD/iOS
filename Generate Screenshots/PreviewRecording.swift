import XCTest
import XCUIPromoKit
import XCUITestKit

/// Plays the App Store preview's script while `promokit record aspen` films the simulator.
///
/// A G2 out of Aspen's runway 33 and back into runway 15: the load typed in, the takeoff distance it
/// gives, the LINDZ departure over the terrain, then the landing distance and its ground run on the
/// map. The take keeps each stretch worth showing and files it under the scene
/// `promo/storyboard.json` frames. Outside `promokit record`, the test skips.
nonisolated final class PreviewRecording: XCTestCase {
  private static let tapLanding: TimeInterval = 0.3,
    tapSettle: TimeInterval = 0.8,
    tabSettle: TimeInterval = 1.2,
    resultsHold: TimeInterval = 3.0,
    chartSettle: TimeInterval = 3.0,
    chartHold: TimeInterval = 3.0,
    mapSettle: TimeInterval = 3.0,
    mapHold: TimeInterval = 3.0

  /// How far each scroll drags the form, as a fraction of its height.
  private static let resultsScroll = 0.55

  private static let payload = "530", takeoffFuel = "212", landingFuel = "75"

  /// A pilot's steady typing on the number pad.
  private static let fuelCadence = TypingCadence(interval: 0.18, jitter: 0.25, seed: 33)

  @MainActor private var app: XCUIApplication!
  @MainActor private var take: PromoTake!

  override func setUpWithError() throws {
    continueAfterFailure = false
  }
}

@MainActor
extension PreviewRecording {

  private var form: XCUIElement { app.collectionViews.firstMatch }

  func testRecordPreview() throws {
    app = XCUIApplication()
    take = try PromoTake(app: app, tapLanding: Self.tapLanding)
    app.launchArguments = PromoLaunch(flags: XCUIApplication.captureLaunchArguments).arguments
    app.launch()

    setUpOpeningShot()
    try take.startRolling()

    take.scene("load") { typeTakeoffFuel() }
    take.scene("takeoff") { revealResult("takeoffDistanceValue") }
    take.scene("climb") { flyLINDZ() }
    take.scene("landing") {
      showTab("Landing")
      revealResult("landingDistanceValue")
    }
    take.scene("map") { showLandingMap() }

    try take.finish()
  }

  // MARK: - Off camera

  /// Downloads what the app needs, fills in the landing, and leaves the takeoff waiting for its fuel
  /// at the top of its form.
  private func setUpOpeningShot() {
    // wait for the Apple Intelligence banner to self-dismiss
    Thread.sleep(forTimeInterval: 30)

    app.completeWelcome()
    app.downloadNorthAmericaTerrain()

    app.tapTab("Landing")
    app.enterLoad(payload: Self.payload, fuel: Self.landingFuel)
    app.selectAspen(runway: "15")
    app.scrollToTop()

    app.tapTab("Takeoff")
    app.selectAspen(runway: "33")
    app.enterLoad(payload: Self.payload, fuel: Self.takeoffFuel)
    clearFuel()
    app.scrollToTop()
  }

  /// Empties the fuel field, so the opening shot types it in.
  private func clearFuel() {
    app.textFields["fuelField"].firstMatch.clearAndType(
      "",
      app: app,
      replacingSelection: true,
      verifying: false,
      doneButtonIdentifier: XCUIElement.numericFieldDoneButton
    )
  }

  /// Brings an element on screen between kept stretches, where the scrolling is never seen.
  private func bringOnScreen(_ element: XCUIElement) -> XCUIElement {
    if element.waitForExistence(timeout: 2), element.isHittable { return element }
    let visible = form.makeVisible(element: element)
    XCTAssertNotNil(visible, "\(element) should be reachable")
    return visible!
  }

  // MARK: - Scenes

  private func typeTakeoffFuel() {
    let fuelField = app.textFields["fuelField"].firstMatch
    take.type(Self.takeoffFuel, into: fuelField, cadence: Self.fuelCadence, settle: Self.tapSettle)
    take.tap(app.buttons[XCUIElement.numericFieldDoneButton], settle: Self.tapSettle)
  }

  /// Scrolls the form up to a result and holds on it.
  private func revealResult(_ identifier: String) {
    let result = app.staticTexts[identifier]
    if !(result.exists && result.isHittable) {
      take.scroll(form, by: Self.resultsScroll, speed: .slow, rest: 0.3)
    }
    XCTAssertTrue(result.isHittable, "\(identifier) should be on screen")
    take.hold(Self.resultsHold)
  }

  /// Opens the climb profile, switches it from a runway-heading climb to the LINDZ departure, and
  /// brings the whole terrain chart into view.
  private func flyLINDZ() {
    let showClimb = bringOnScreen(app.buttons["showClimbProfileButton"])
    let climbNavBar = app.navigationBars["Climb Profile"], tapPoint = showClimb.frame.center
    take.keepTail(settle: Self.tabSettle) {
      // The link sits just above the tab bar and ignores a plain synthesized tap.
      tapAndEnsureNavigation(element: showClimb, expectedElement: climbNavBar)
      take.noteTap(at: tapPoint)
      Thread.sleep(forTimeInterval: Self.tabSettle)
    }

    let typePicker = app.descendants(matching: .any)["departureTypePicker"].firstMatch
    let procedure = app.buttons["Procedure"]
    XCTAssertTrue(typePicker.waitForExistence(timeout: 10), "Departure type picker should appear")
    take.openAndHold(typePicker, revealing: procedure, for: Self.tapSettle)
    take.tap(procedure, settle: Self.chartSettle)

    let chart = app.descendants(matching: .any)["terrainProfileChart"].firstMatch
    XCTAssertTrue(chart.waitForExistence(timeout: 30), "Terrain chart should appear")
    take.keep { app.scrollIntoFullView(chart) }
    take.hold(Self.chartHold)
  }

  private func showTab(_ tab: String) {
    take.tap(app.buttons[tab].firstMatch, settle: Self.tabSettle)
  }

  private func showLandingMap() {
    let showMap = bringOnScreen(app.buttons["showLandingMapButton"])
    take.tap(showMap, settle: Self.mapSettle)
    take.hold(Self.mapHold)
  }
}

extension CGRect {
  fileprivate var center: CGPoint { CGPoint(x: midX, y: midY) }
}
