import XCTest
import XCUITestKit

/// Steps that bring the app to the state the screenshots and the preview are captured in: a G2
/// with nav data and North America terrain, flying out of and back into Aspen.
@MainActor
extension XCUIApplication {

  /// KASE's NASR record ID (its FAA site number). Seeding it as a favorite lets the flow select
  /// Aspen from the Favorites tab instead of searching for it: the search keyboard and search bar
  /// orphan themselves over the popped-to form on iOS 26 under a fresh run's load and block the
  /// runway picker.
  static let aspenRecordID = "02517.*A"

  /// Room, in points, left between the terrain chart and the bars around it when it is scrolled
  /// into full view: enough above it for the weather pills, and a little below it.
  private static let chartHeadroom: CGFloat = 60, chartFootroom: CGFloat = 12

  /// The launch arguments every capture starts from.
  static let captureLaunchArguments = [
    "UI-TESTING", "GENERATE-SCREENSHOTS", "FAVORITE-AIRPORTS=\(aspenRecordID)"
  ]

  /// Sets up a G2 on the welcome screen, if it shows, and downloads nav data when offered.
  func completeWelcome() {
    completeWelcome {}
  }

  /// Sets up a G2 on the welcome screen, if it shows, and downloads nav data when offered.
  ///
  /// - Parameter beforeContinuing: Runs once the aircraft is set up, before leaving the welcome
  ///   screen.
  func completeWelcome(beforeContinuing: () throws -> Void) rethrows {
    guard buttons["continueButton"].waitForExistence(timeout: 5) else { return }

    let modelPicker = segmentedControls["modelPicker"]
    if modelPicker.waitForExistence(timeout: 2) {
      modelPicker.buttons["G2"].tap()
    }

    let emptyWeightField = textFields["emptyWeightField"]
    XCTAssertTrue(
      emptyWeightField.waitForExistence(timeout: 2),
      "Empty weight field should be accessible"
    )
    emptyWeightField.enter("3606", app: self)

    // Dismiss keyboard popover on iPad
    if otherElements["PopoverDismissRegion"].exists {
      otherElements["PopoverDismissRegion"].tap()
    }

    try beforeContinuing()
    buttons["continueButton"].tap()

    if buttons["downloadDataButton"].waitForExistence(timeout: 5) {
      buttons["downloadDataButton"].tap()

      // Wait for loader to complete and main view to appear (may take 30+ minutes)
      XCTAssertTrue(
        textFields["payloadField"].waitForExistence(timeout: 3600),
        "Payload field should appear after airport data download completes"
      )
    } else {
      XCTAssertTrue(
        textFields["payloadField"].waitForExistence(timeout: 10),
        "Payload field should appear"
      )
    }
  }

  /// Downloads North America's terrain from Settings, unless it's already downloaded.
  func downloadNorthAmericaTerrain() {
    tapTab("Settings")

    let terrainLink = collectionViews.firstMatch.makeVisible(
      element: buttons["terrainNavigationLink"]
    )
    XCTAssertNotNil(terrainLink, "Terrain navigation link should be accessible")
    terrainLink!.forceTap()

    let naDownloaded = images["terrainDownloaded-na"]
    guard !naDownloaded.waitForExistence(timeout: 5) else { return }

    // Waits out a download an earlier run left going, as well as one started here.
    let naDownloadButton = buttons["terrainDownload-na"]
    if naDownloadButton.exists { naDownloadButton.tap() }

    // Can take 30+ minutes on erased simulators
    XCTAssertTrue(
      naDownloaded.waitForExistence(timeout: 3600),
      "North America terrain should finish downloading"
    )
  }

  /// Fills in the open performance tab's payload and fuel.
  ///
  /// - Parameters:
  ///   - payload: The payload to enter, in pounds.
  ///   - fuel: The fuel to enter, in gallons.
  func enterLoad(payload: String, fuel: String) {
    let payloadField = textFields["payloadField"].firstMatch
    XCTAssertTrue(payloadField.waitForExistence(timeout: 5), "Payload field should be accessible")
    payloadField.enter(payload, app: self)

    let fuelField = textFields["fuelField"].firstMatch
    XCTAssertTrue(fuelField.waitForExistence(timeout: 5), "Fuel field should be accessible")
    fuelField.enter(fuel, app: self)
  }

  /// Selects Aspen, from the Favorites tab, and one of its runways on the open performance tab.
  ///
  /// - Parameter runway: The runway to select, such as `"33"`.
  func selectAspen(runway: String) {
    let airportSelector = collectionViews.firstMatch.makeVisible(
      element: buttons["airportSelector"]
    )
    XCTAssertNotNil(airportSelector, "Airport selector should be accessible")
    tapAndEnsureNavigation(
      element: airportSelector!,
      expectedElement: segmentedControls["airportListPicker"]
    )

    // Selecting from Favorites leaves the search field untouched, avoiding the orphaned search
    // keyboard that otherwise floats over the popped-to form and swallows the tap that opens the
    // runway picker.
    let airportRow = buttons["airportRow-ASE"].firstMatch
    XCTAssertTrue(airportRow.waitForExistence(timeout: 10), "ASE favorite should appear")
    airportRow.tap()

    let runwaySelector = collectionViews.firstMatch.makeVisible(
      element: buttons["runwaySelector"]
    )
    XCTAssertNotNil(runwaySelector, "Runway selector should be accessible")

    // Opened with robust navigation, so the Liquid Glass bar can't swallow the tap that
    // presents it.
    let runwayRow = buttons["runwayRow-\(runway)"].firstMatch
    tapAndEnsureNavigation(element: runwaySelector!, expectedElement: runwayRow)
    XCTAssertTrue(runwayRow.waitForExistence(timeout: 2), "Runway \(runway) should appear")
    runwayRow.tap()
  }

  /// Turns on the climb profile's weather: the temperature field behind the terrain, and the
  /// along-track wind barbs over it.
  ///
  /// Best-effort throughout — a capture of a bare chart beats a failed run.
  func showWeatherLayers() {
    selectFromPill("weatherLayerPicker", option: "Temperature")
    selectFromPill("windBarbsPicker", option: "On")
  }

  /// Switches the climb profile's departure to the published LINDZ procedure at KASE, so the
  /// terrain chart shows real departure routing instead of a straight-out runway-heading climb.
  ///
  /// Best-effort: if LINDZ isn't published for the selected runway, the first plottable departure
  /// stays auto-selected.
  func selectLINDZDeparture() {
    let typePicker = descendants(matching: .any)["departureTypePicker"].firstMatch
    guard typePicker.waitForExistence(timeout: 5) else { return }

    let procedureOption = buttons["Procedure"]
    guard typePicker.tap(untilExists: procedureOption, using: XCUIElement.TapStrategy.escalating)
    else { return }
    procedureOption.forceTap()

    let sidPicker = descendants(matching: .any)["departureProcedurePicker"].firstMatch
    guard sidPicker.waitForExistence(timeout: 5) else { return }

    // The first plottable SID auto-selects, which at KASE is LINDZ. If it's already chosen, leave
    // the menu closed — re-picking it risks the menu lingering open in the capture.
    let currentSID = "\(sidPicker.label) \((sidPicker.value as? String) ?? "")"
    if currentSID.localizedCaseInsensitiveContains("LINDZ") { return }

    // Match the menu option, not the picker cell (whose label carries the selected SID), so the
    // closing tap dismisses the menu instead of reopening it.
    let lindz =
      buttons
      .matching(
        NSPredicate(
          format: "label CONTAINS[c] %@ AND identifier != %@",
          "LINDZ",
          "departureProcedurePicker"
        )
      )
      .firstMatch
    if sidPicker.tap(untilExists: lindz, using: XCUIElement.TapStrategy.escalating) {
      lindz.forceTap()
    }
  }

  /// Drags the list up until the whole chart clears the tab bar, without pushing the pills above it
  /// under the navigation bar.
  ///
  /// - Parameter chart: The terrain chart.
  func scrollIntoFullView(_ chart: XCUIElement) {
    let tabBar = tabBars.firstMatch, navigationBar = navigationBars.firstMatch
    guard chart.exists, tabBar.exists, navigationBar.exists else { return }

    let hiddenBelow = chart.frame.maxY + Self.chartFootroom - tabBar.frame.minY
    let roomAbove = chart.frame.minY - Self.chartHeadroom - navigationBar.frame.maxY
    let distance = min(hiddenBelow, roomAbove)
    guard distance > 0 else { return }

    let start = collectionViews.firstMatch.coordinate(
      withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
    )
    start.press(
      forDuration: 0.1,
      thenDragTo: start.withOffset(CGVector(dx: 0, dy: -distance)),
      withVelocity: .slow,
      thenHoldForDuration: 0.5
    )
  }

  /// Taps the back button, which the iPhone Duo's outer display moves out of the navigation bar
  /// and into a rail beside the content.
  func goBack() {
    buttons["BackButton"].firstMatch.forceTap()
  }

  /// Picks an option from one of the climb chart's weather pull-downs.
  ///
  /// - Parameters:
  ///   - identifier: The pill's accessibility identifier.
  ///   - option: The menu item to choose.
  private func selectFromPill(_ identifier: String, option: String) {
    let pill = descendants(matching: .any)[identifier].firstMatch
    guard pill.waitForExistence(timeout: 10) else { return }

    let menuItem = buttons[option].firstMatch
    guard pill.tap(untilExists: menuItem, using: XCUIElement.TapStrategy.escalating) else { return }
    menuItem.forceTap()
  }
}
