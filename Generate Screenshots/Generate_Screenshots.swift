//
//  Generate_Screenshots.swift
//  Generate Screenshots
//
//  Created by Tim Morgan on 10/5/25.
//

import UIKit
import XCTest
import XCUITestKit

final class Generate_Screenshots: XCTestCase {

  /// KASE's NASR record ID (its FAA site number). Seeding it as a favorite lets
  /// the flow select Aspen from the Favorites tab instead of the airport search
  /// field, whose keyboard and search bar orphan themselves over the popped-to
  /// form on iOS 26 under a fresh run's load and block the runway picker.
  private static let aspenRecordID = "02517.*A"

  private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

  override func setUpWithError() throws {
    // In UI tests it is usually best to stop immediately when a failure occurs.
    continueAfterFailure = false
  }

  override func tearDownWithError() throws {
  }

  func testGenerateScreenshots() throws {
    let app = XCUIApplication()
    app.launchArguments = [
      "UI-TESTING", "GENERATE-SCREENSHOTS", "FAVORITE-AIRPORTS=\(Self.aspenRecordID)"
    ]
    setupSnapshot(app)
    app.launch()

    // Handle location permission directly via springboard
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    if springboard.alerts.buttons["Allow While Using App"].waitForExistence(timeout: 5) {
      springboard.alerts.buttons["Allow While Using App"].tap()
    }

    // wait for Apple Intelligence banner to self-dismiss
    Thread.sleep(forTimeInterval: 30)

    // Wait for welcome screen to appear (should always appear on first test run)
    if app.buttons["continueButton"].waitForExistence(timeout: 5) {
      // Welcome screen appeared - go through setup flow

      // Set model to G2
      let modelPicker = app.segmentedControls["modelPicker"]
      if modelPicker.waitForExistence(timeout: 2) {
        modelPicker.buttons["G2"].tap()
      }

      // Set empty weight
      let emptyWeightField = app.textFields["emptyWeightField"]
      XCTAssertTrue(
        emptyWeightField.waitForExistence(timeout: 2),
        "Empty weight field should be accessible"
      )
      emptyWeightField.clearAndType("3606", app: app)

      // Dismiss keyboard popover on iPad
      if app.otherElements["PopoverDismissRegion"].exists {
        app.otherElements["PopoverDismissRegion"].tap()
      }

      snapshot("01-aircraft-setup")

      app.buttons["continueButton"].tap()

      // Check if download consent screen appears and tap download button to download live airport data
      if app.buttons["downloadDataButton"].waitForExistence(timeout: 5) {
        app.buttons["downloadDataButton"].tap()

        // Wait for loader to complete and main view to appear (may take 30+ minutes)
        XCTAssertTrue(
          app.textFields["payloadField"].waitForExistence(timeout: 3600),
          "Payload field should appear after airport data download completes"
        )
      } else {
        // Download button didn't appear - data may already be downloaded, just wait for main view
        XCTAssertTrue(
          app.textFields["payloadField"].waitForExistence(timeout: 10),
          "Payload field should appear"
        )
      }
    }

    // Download NA terrain data
    app.tapTab("Settings")

    // Terrain link may be below the fold — scroll to find it
    let terrainLink = app.collectionViews.firstMatch.makeVisible(
      element: app.buttons["terrainNavigationLink"]
    )
    XCTAssertNotNil(terrainLink, "Terrain navigation link should be accessible")
    terrainLink!.forceTap()

    // Tap Download for North America (skip if already downloaded)
    let naDownloadButton = app.buttons["terrainDownload-na"]
    if naDownloadButton.waitForExistence(timeout: 5) {
      naDownloadButton.tap()

      // Wait for download to complete (can take 20+ minutes on erased simulators)
      let naDownloadedCheckmark = app.images["terrainDownloaded-na"]
      XCTAssertTrue(
        naDownloadedCheckmark.waitForExistence(timeout: 1800),
        "North America terrain should finish downloading"
      )
    }

    // Navigate back to Takeoff tab
    app.tapTab("Takeoff")

    // Configure takeoff parameters
    let payloadField = app.textFields["payloadField"].firstMatch
    XCTAssertTrue(payloadField.waitForExistence(timeout: 5), "Payload field should be accessible")
    payloadField.clearAndType("530", app: app)

    let fuelField = app.textFields["fuelField"].firstMatch
    XCTAssertTrue(fuelField.waitForExistence(timeout: 5), "Fuel field should be accessible")
    fuelField.clearAndType("212", app: app)

    // Select airport first (needed before weather selector is available)
    let airportSelector = app.collectionViews.firstMatch.makeVisible(
      element: app.buttons["airportSelector"]
    )
    XCTAssertNotNil(airportSelector, "Airport selector should be accessible")

    // Tap and ensure navigation (may need double-tap on some devices)
    tapAndEnsureNavigation(
      element: airportSelector!,
      expectedElement: app.segmentedControls["airportListPicker"]
    )

    // Select KASE from the Favorites tab (the picker's default), where it is
    // seeded via the FAVORITE-AIRPORTS launch argument. The Favorites list has
    // no `.searchable` field, so selecting from it avoids the orphaned search
    // keyboard that otherwise floats over the popped-to form and swallows the
    // tap that opens the runway picker.
    let takeoffAirportRow = app.buttons["airportRow-ASE"].firstMatch
    XCTAssertTrue(
      takeoffAirportRow.waitForExistence(timeout: 10),
      "ASE favorite should appear"
    )
    takeoffAirportRow.tap()

    // Select runway
    let runwaySelector = app.collectionViews.firstMatch.makeVisible(
      element: app.buttons["runwaySelector"]
    )
    XCTAssertNotNil(runwaySelector, "Runway selector should be accessible")

    // Open the runway picker with the same robust navigation the airport selector
    // uses, so the iOS 26 Liquid Glass bar can't swallow the tap that presents it.
    let takeoffRunwayRow = app.buttons["runwayRow-33"].firstMatch
    tapAndEnsureNavigation(element: runwaySelector!, expectedElement: takeoffRunwayRow)
    XCTAssertTrue(takeoffRunwayRow.waitForExistence(timeout: 2), "Runway 33 should appear")
    takeoffRunwayRow.tap()

    // Scroll to top to show all configured parameters
    app.scrollToTop()

    snapshot("02-takeoff-params")

    // Now weather selector should be available
    let weatherSelector = app.collectionViews.firstMatch.makeVisible(
      element: app.buttons["weatherSelector"]
    )
    XCTAssertNotNil(weatherSelector, "Weather selector should be accessible")

    // Open the weather picker with robust navigation so the iOS 26 Liquid Glass
    // bar can't swallow the tap that presents it.
    let windField = app.textFields["windDirectionField"].firstMatch
    tapAndEnsureNavigation(element: weatherSelector!, expectedElement: windField)

    snapshot("10-weather")

    // Go back from weather
    app.navigationBars.buttons.element(boundBy: 0).forceTap()

    // Verify takeoff distances are displayed
    let takeoffGroundRun = app.staticTexts["takeoffGroundRunValue"]
    let takeoffDistance = app.staticTexts["takeoffDistanceValue"]

    // On a phone the results sit below the fold, so scroll down and capture them
    // as a separate screenshot. On iPad the whole takeoff view fits on one screen
    // (02 already shows the results), so the scrolled capture is redundant.
    if !isPad {
      let takeoffCollectionView = app.collectionViews.firstMatch
      var takeoffScrollAttempts = 0
      while takeoffScrollAttempts < 3 {
        takeoffCollectionView.swipeUp()
        Thread.sleep(forTimeInterval: 0.3)
        takeoffScrollAttempts += 1
      }
    }

    XCTAssertTrue(
      takeoffGroundRun.waitForExistence(timeout: 2),
      "Takeoff ground run should be displayed"
    )
    XCTAssertTrue(
      takeoffDistance.waitForExistence(timeout: 2),
      "Takeoff distance should be displayed"
    )

    if !isPad {
      snapshot("03-takeoff-results")
    }

    // Generate takeoff report
    let takeoffReportButton = app.collectionViews.firstMatch.makeVisible(
      element: app.buttons["generateTakeoffReportButton"]
    )
    XCTAssertNotNil(takeoffReportButton, "Generate takeoff report button should be accessible")

    // Present the report sheet with robust navigation, waiting for its web view so
    // the snapshot captures rendered content.
    tapAndEnsureNavigation(
      element: takeoffReportButton!,
      expectedElement: app.webViews.firstMatch
    )

    snapshot("04-takeoff-report")

    // Dismiss the report sheet via its Done button, the same reliable path the
    // regular UI suite uses. A coordinate swipe-down is unreliable on iOS 26: the
    // embedded web view swallows the drag, leaving the sheet up to intercept the
    // next tap so the climb-profile navigation never fires.
    let doneButton = app.buttons["Done"].firstMatch
    if doneButton.waitForExistence(timeout: 5) {
      doneButton.forceTap()
    }

    // Confirm the sheet is gone before continuing so its web view can't swallow
    // the climb-profile tap.
    _ = app.webViews.firstMatch.waitForNonExistence(timeout: 10)

    // Show climb profile
    let showClimbButton = app.collectionViews.firstMatch.makeVisible(
      element: app.buttons["showClimbProfileButton"]
    )
    if let showClimbButton, showClimbButton.isEnabled {
      let climbNavBar = app.navigationBars["Climb Profile"]

      // The climb NavigationLink sits just above the Liquid Glass tab bar and, on this
      // data-heavy screen, ignores a synthesized forceTap. tapAndEnsureNavigation escalates
      // through held-press and coordinate-press strategies until the climb screen pushes.
      tapAndEnsureNavigation(element: showClimbButton, expectedElement: climbNavBar)

      // Best-effort: capturing the climb profile must not abort the whole run, so
      // skip its snapshot rather than fail if the push never registers.
      if climbNavBar.waitForExistence(timeout: 20) {
        selectLINDZDeparture(in: app)

        let terrainChart = app.descendants(matching: .any)["terrainProfileChart"]
        _ = terrainChart.waitForExistence(timeout: 30)

        showWeatherLayers(in: app)

        Thread.sleep(forTimeInterval: 2.0)
        snapshot("05-climb-profile")

        // Navigate back
        app.navigationBars.buttons.element(boundBy: 0).forceTap()
      }
    }

    // Navigate to Landing tab
    app.tapTab("Landing")

    // Configure landing parameters
    let landingPayloadField = app.textFields["payloadField"].firstMatch
    XCTAssertTrue(
      landingPayloadField.waitForExistence(timeout: 5),
      "Payload field should be accessible"
    )
    landingPayloadField.clearAndType("530", app: app)

    let landingFuelField = app.textFields["fuelField"].firstMatch
    XCTAssertTrue(landingFuelField.waitForExistence(timeout: 5), "Fuel field should be accessible")
    landingFuelField.clearAndType("75", app: app)

    // Select airport for landing
    let landingAirportSelector = app.collectionViews.firstMatch.makeVisible(
      element: app.buttons["airportSelector"]
    )
    XCTAssertNotNil(landingAirportSelector, "Landing airport selector should be accessible")

    // Tap and ensure navigation (may need double-tap on some devices)
    tapAndEnsureNavigation(
      element: landingAirportSelector!,
      expectedElement: app.segmentedControls["airportListPicker"]
    )

    // Select KASE from the Favorites tab (see the takeoff flow above).
    let landingAirportRow = app.buttons["airportRow-ASE"].firstMatch
    if landingAirportRow.waitForExistence(timeout: 10) {
      landingAirportRow.tap()
    }

    // Select runway for landing
    let landingRunwaySelector = app.collectionViews.firstMatch.makeVisible(
      element: app.buttons["runwaySelector"]
    )
    XCTAssertNotNil(landingRunwaySelector, "Landing runway selector should be accessible")

    // Open the runway picker with robust navigation so the iOS 26 Liquid Glass
    // bar can't swallow the tap that presents it.
    let landingRunwayRow = app.buttons["runwayRow-15"].firstMatch
    tapAndEnsureNavigation(element: landingRunwaySelector!, expectedElement: landingRunwayRow)
    if landingRunwayRow.waitForExistence(timeout: 2) {
      landingRunwayRow.tap()
    }

    // Scroll to top to show configured parameters
    app.scrollToTop()
    Thread.sleep(forTimeInterval: 0.5)

    snapshot("06-landing-params")

    // Verify landing distance is displayed
    let landingDistance = app.staticTexts["landingDistanceValue"]

    // Phone-only scrolled results capture (see takeoff above); on iPad the
    // landing results are visible without scrolling, so 06 already covers them.
    let collectionView = app.collectionViews.firstMatch
    if !isPad {
      var scrollAttempts = 0
      while scrollAttempts < 3 {
        collectionView.swipeUp()
        Thread.sleep(forTimeInterval: 0.3)
        scrollAttempts += 1
      }
    }

    XCTAssertTrue(
      landingDistance.waitForExistence(timeout: 2),
      "Landing distance should be displayed"
    )

    if !isPad {
      snapshot("07-landing-results")
    }

    // Show landing map view
    let showLandingMapButton = collectionView.makeVisible(
      element: app.buttons["showLandingMapButton"]
    )
    XCTAssertNotNil(showLandingMapButton, "Show landing map button should be accessible")
    XCTAssertTrue(
      showLandingMapButton!.isEnabled,
      "Show landing map button should be enabled (runway must have threshold coordinates)"
    )
    showLandingMapButton!.forceTap()

    // Wait for map to render
    Thread.sleep(forTimeInterval: 2.0)

    snapshot("08-landing-map")

    // Go back from map view
    let mapBackButton = app.navigationBars.buttons.element(boundBy: 0)
    XCTAssertTrue(mapBackButton.waitForExistence(timeout: 5), "Map view back button should exist")
    mapBackButton.forceTap()

    // Navigate to Climb tab
    app.tapTab("Climb")

    snapshot("09-climb")
  }

  // MARK: - Helpers

  /// Turn on the climb profile's weather so the chart is captured showing what it can do: the
  /// temperature field behind the terrain, and the along-track wind barbs over it.
  ///
  /// Best-effort throughout — a screenshot of a bare chart beats a failed run.
  private func showWeatherLayers(in app: XCUIApplication) {
    selectFromPill("weatherLayerPicker", option: "Temperature", in: app)
    selectFromPill("windBarbsPicker", option: "On", in: app)
  }

  /// Pick an option from one of the chart's weather pull-downs.
  ///
  /// - Parameters:
  ///   - identifier: The pill's accessibility identifier.
  ///   - option: The menu item to choose.
  ///   - app: The application under test.
  private func selectFromPill(_ identifier: String, option: String, in app: XCUIApplication) {
    let pill = app.descendants(matching: .any)[identifier].firstMatch
    guard pill.waitForExistence(timeout: 10) else { return }

    let menuItem = app.buttons[option].firstMatch
    guard pill.tap(untilExists: menuItem, using: XCUIElement.TapStrategy.escalating) else { return }
    menuItem.forceTap()
  }

  /// Switch the climb profile's departure to the published LINDZ procedure at
  /// KASE so the terrain chart shows real departure routing instead of a
  /// straight-out runway-heading climb. Best-effort: if LINDZ isn't published for
  /// the selected runway, the first plottable departure stays auto-selected.
  private func selectLINDZDeparture(in app: XCUIApplication) {
    let typePicker = app.descendants(matching: .any)["departureTypePicker"].firstMatch
    guard typePicker.waitForExistence(timeout: 5) else { return }

    let procedureOption = app.buttons["Procedure"]
    guard typePicker.tap(untilExists: procedureOption, using: XCUIElement.TapStrategy.escalating)
    else { return }
    procedureOption.forceTap()

    let sidPicker = app.descendants(matching: .any)["departureProcedurePicker"].firstMatch
    guard sidPicker.waitForExistence(timeout: 5) else { return }

    // The first plottable SID auto-selects, which at KASE is LINDZ. If it's
    // already chosen, leave the menu closed — re-picking it risks the menu
    // lingering open in the snapshot. Only open the picker to correct a
    // different auto-selection.
    let currentSID = "\(sidPicker.label) \((sidPicker.value as? String) ?? "")"
    if currentSID.localizedCaseInsensitiveContains("LINDZ") { return }

    // Match the menu option, not the picker cell (whose label carries the
    // selected SID), so the closing tap dismisses the menu instead of reopening.
    let lindz = app.buttons
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
}
