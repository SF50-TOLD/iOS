public import Foundation
import SwiftData

extension Airport {
  /// The number of airports a free-text search returns.
  public static let searchResultLimit = 10

  /// A predicate matching airports against free-text search terms.
  ///
  /// An identifier match is exact and case-insensitive; a name or city match is a substring. This is
  /// the fetch half of a search — ``relevanceScore(for:searchText:)`` orders what it returns.
  ///
  /// - Parameter searchText: The text the person typed.
  /// - Returns: A predicate suitable for a `FetchDescriptor<Airport>`.
  public static func searchPredicate(matching searchText: String) -> Predicate<Airport> {
    let uppercaseText = searchText.uppercased()
    return #Predicate<Airport> { airport in
      airport.locationID == uppercaseText
        || airport.name.localizedStandardContains(searchText)
        || airport.ICAO_ID == uppercaseText
        || airport.city?.localizedStandardContains(searchText) == true
    }
  }

  /// How well an airport matches the search text, higher being better.
  ///
  /// An exact identifier match outranks a name match, which outranks a city match. Callers that want a
  /// stable order should break ties on the airport name.
  ///
  /// - Parameters:
  ///   - airport: The airport to score.
  ///   - searchText: The text the person typed.
  /// - Returns: 3 for an exact identifier match, 2 for a name match, 1 for a city match, else 0.
  public static func relevanceScore(for airport: Airport, searchText: String) -> Int {
    if airport.locationID == searchText.uppercased() { return 3 }
    if let ICAO_ID = airport.ICAO_ID, ICAO_ID == searchText.uppercased() { return 3 }
    if airport.name.localizedStandardContains(searchText) { return 2 }
    if let city = airport.city, city.localizedStandardContains(searchText) { return 1 }
    return 0
  }
}
