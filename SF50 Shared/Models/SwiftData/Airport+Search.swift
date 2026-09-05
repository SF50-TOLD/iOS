public import Foundation
import SwiftData

extension Airport {
  /// The number of airports a free-text search returns.
  public static let searchResultLimit = 10

  /// A predicate matching airports against free-text search terms.
  ///
  /// An identifier match is exact and case-insensitive; a name or city match is a substring. This is
  /// the fetch half of a search — ``ranked(_:matching:)`` orders what it returns.
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

  /// Orders search results the way every airport picker in the app presents them.
  ///
  /// The app's own picker and the App Intents query both call this, so an identifier typed into
  /// Shortcuts ranks the way it does in the app rather than merely alphabetically. Airports sort by
  /// match kind first, then by how much of the name or city the text covers, then by name.
  ///
  /// - Parameters:
  ///   - airports: The airports ``searchPredicate(matching:)`` fetched.
  ///   - searchText: The text the person typed.
  /// - Returns: At most ``searchResultLimit`` airports, best match first.
  public static func ranked(_ airports: [Airport], matching searchText: String) -> [Airport] {
    // Scoring once per airport rather than inside the comparator keeps this O(n) instead of O(n log n).
    let scored = airports.map {
      (
        airport: $0,
        relevance: relevanceScore(for: $0, searchText: searchText),
        similarity: similarityScore(for: $0, searchText: searchText)
      )
    }

    return
      scored
      .sorted { left, right in
        if left.relevance != right.relevance { return left.relevance > right.relevance }
        if left.similarity != right.similarity { return left.similarity > right.similarity }
        return left.airport.name.localizedStandardCompare(right.airport.name) == .orderedAscending
      }
      .prefix(searchResultLimit)
      .map(\.airport)
  }

  /// How well an airport matches the search text, higher being better.
  ///
  /// An exact identifier match outranks a name match, which outranks a city match. Airports scoring
  /// the same here are separated by how much of the name or city the text actually covers.
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

  /// How much of an airport's name or city the search text covers, from 0 to 1.
  ///
  /// A whole-name match beats a prefix, which beats a substring; a city match is worth less than the
  /// same kind of name match. This is what puts “Oakland Intl” above “Metro Oakland Airport” for
  /// someone typing “Oakland”, where the match kind alone leaves them tied.
  ///
  /// - Parameters:
  ///   - airport: The airport to score.
  ///   - searchText: The text the person typed.
  /// - Returns: The better of the name and city similarities.
  static func similarityScore(for airport: Airport, searchText: String) -> Double {
    max(
      nameSimilarity(airport.name, to: searchText),
      citySimilarity(airport.city, to: searchText)
    )
  }

  private static func nameSimilarity(_ name: String, to searchText: String) -> Double {
    if name.localizedStandardEquals(searchText) { return 1.0 }
    if name.localizedStandardHasPrefix(searchText) { return 0.8 }
    if name.localizedStandardContains(searchText) { return 0.6 }

    let commonCharacters = Set(name.localizedLowercase)
      .intersection(Set(searchText.localizedLowercase))
      .count
    return Double(commonCharacters) / Double(max(name.count, searchText.count)) * 0.4
  }

  private static func citySimilarity(_ city: String?, to searchText: String) -> Double {
    guard let city else { return 0.0 }
    if city.localizedStandardEquals(searchText) { return 0.5 }
    if city.localizedStandardHasPrefix(searchText) { return 0.4 }
    if city.localizedStandardContains(searchText) { return 0.3 }
    return 0.0
  }
}
