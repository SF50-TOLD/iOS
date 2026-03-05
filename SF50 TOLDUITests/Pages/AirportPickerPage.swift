// swiftlint:disable prefer_nimble
import XCTest

final class AirportPickerPage: BasePage {

  private var segmentedControl: XCUIElement {
    app.segmentedControls["airportListPicker"]
  }

  // MARK: - Tab Switching

  func switchToFavorites() {
    XCTAssertTrue(segmentedControl.waitForExistence(timeout: 2), "Airport picker should appear")
    segmentedControl.buttons["Favorites"].tap()
  }

  func switchToRecents() {
    XCTAssertTrue(segmentedControl.waitForExistence(timeout: 2), "Airport picker should appear")
    segmentedControl.buttons["Recents"].tap()
  }

  func switchToSearch() {
    XCTAssertTrue(segmentedControl.waitForExistence(timeout: 2), "Airport picker should appear")
    segmentedControl.buttons["Search"].tap()
  }

  // MARK: - Actions

  func search(for query: String) {
    let searchField = app.searchFields.firstMatch

    // On iOS 26, .searchable renders at the bottom in compact form.
    // It may need a swipe-up or tap to expand.
    if !searchField.waitForExistence(timeout: 5) {
      // Try scrolling to reveal the search field
      app.swipeUp()
      _ = searchField.waitForExistence(timeout: 3)
    }

    XCTAssertTrue(searchField.exists, "Search field should appear")

    // Tap the search field and wait for keyboard to gain focus
    for _ in 0..<3 {
      searchField.tap()
      if app.keyboards.firstMatch.waitForExistence(timeout: 2) { break }
    }

    searchField.typeText(query)
  }

  func selectAirport(_ identifier: String) {
    let row = app.buttons["airportRow-\(identifier)"].firstMatch
    XCTAssertTrue(
      row.waitForExistence(timeout: 3),
      "\(identifier) should appear in results"
    )
    row.tap()
  }

  func searchAndSelect(_ identifier: String) {
    switchToSearch()
    search(for: identifier)
    selectAirport(identifier)
  }

  override func dismissKeyboard() {
    let keyboardSearchButton = app.keyboards.buttons["Search"].firstMatch
    if keyboardSearchButton.exists {
      keyboardSearchButton.tap()
    } else {
      app.searchFields.firstMatch.typeText("\n")
    }
  }

  func toggleFavorite(for identifier: String) {
    let allButtons = app.buttons.matching(identifier: "airportRow-\(identifier)")
    let favoriteButton = allButtons.element(boundBy: 2)
    XCTAssertTrue(favoriteButton.exists, "Favorite button should exist")

    if favoriteButton.isHittable {
      favoriteButton.tap()
    } else {
      favoriteButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }
  }

  // MARK: - Queries

  func isAirportVisible(_ identifier: String) -> Bool {
    app.buttons["airportRow-\(identifier)"].exists
  }

  func airportRowCount() -> Int {
    app.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH 'airportRow-'")
    ).count
  }
}
// swiftlint:enable prefer_nimble
