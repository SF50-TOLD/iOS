// swiftlint:disable prefer_nimble
import XCTest

final class AirportPickerPage: BasePage {

  private var segmentedControl: XCUIElement { app.airportListPicker() }

  // MARK: - Tab Switching

  func switchToFavorites() {
    XCTAssertTrue(segmentedControl.waitForExistence(timeout: 5), "Airport picker should appear")
    let button = segmentedControl.buttons["Favorites"]
    ensureHittable(button)
    forceTap(button)
  }

  func switchToRecents() {
    XCTAssertTrue(segmentedControl.waitForExistence(timeout: 5), "Airport picker should appear")
    let button = segmentedControl.buttons["Recents"]
    ensureHittable(button)
    forceTap(button)
  }

  func switchToSearch() {
    XCTAssertTrue(segmentedControl.waitForExistence(timeout: 5), "Airport picker should appear")
    let button = segmentedControl.buttons["Search"]
    ensureHittable(button)
    forceTap(button)
  }

  // MARK: - Actions

  func search(for query: String) {
    revealSearchField()
    let searchField = app.searchFields.firstMatch
    XCTAssertTrue(searchField.exists, "Search field should appear")

    // Tap the search field and wait for keyboard to gain focus
    for _ in 0..<3 {
      forceTap(searchField)
      if app.keyboards.firstMatch.waitForExistence(timeout: 2) { break }
    }

    searchField.typeText(query)
  }

  /// Surfaces the `.searchable` text field, whose presentation depends on size class.
  ///
  /// In compact width (iPhone) the field is inline and may sit offscreen, so a
  /// swipe-up reveals it. In regular width (iPad) it collapses into a
  /// navigation-bar search button that must be tapped to expand into the field.
  private func revealSearchField() {
    let searchField = app.searchFields.firstMatch
    if searchField.waitForExistence(timeout: 5) { return }

    // Retry to absorb the slow Liquid Glass nav-bar settle under full-suite
    // load, during which the collapsed search button is briefly unhittable.
    for _ in 0..<3 {
      let searchButton = app.navigationBars.buttons["Search"].firstMatch
      if searchButton.exists {
        if waitForHittable(searchButton, timeout: 3) { forceTap(searchButton) }
      } else {
        app.swipeUp()
      }
      if searchField.waitForExistence(timeout: 3) { return }
    }
  }

  func selectAirport(_ identifier: String) {
    let row = app.buttons["airportRow-\(identifier)"].firstMatch
    XCTAssertTrue(
      row.waitForExistence(timeout: 3),
      "\(identifier) should appear in results"
    )
    forceTap(row)
  }

  func searchAndSelect(_ identifier: String) {
    switchToSearch()
    search(for: identifier)
    selectAirport(identifier)
  }

  override func dismissKeyboard() {
    let keyboardSearchButton = app.keyboards.buttons["Search"].firstMatch
    if keyboardSearchButton.exists {
      forceTap(keyboardSearchButton)
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
