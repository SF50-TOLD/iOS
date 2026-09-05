import Foundation
import Testing

@testable import SF50_Shared

/// The airport picker and the App Intents airport query share one ranking so a shortcut and the app
/// agree on what "OAK" means. These pin the order that sharing has to preserve.
@Suite
struct `Airport Search` {
  private static func airport(
    locationID: String,
    ICAO_ID: String? = nil,
    name: String,
    city: String? = nil
  ) -> Airport {
    .init(
      recordID: locationID,
      locationID: locationID,
      ICAO_ID: ICAO_ID,
      name: name,
      city: city,
      dataSource: .NASR,
      latitude: .init(value: 37, unit: .degrees),
      longitude: .init(value: -122, unit: .degrees),
      elevation: .init(value: 0, unit: .feet),
      variation: .init(value: 0, unit: .degrees)
    )
  }

  /// The order both `AirportEntityQuery` and `SearchViewModel` present, named by identifier.
  private static func ranked(_ airports: [Airport], matching searchText: String) -> [String] {
    Airport.ranked(airports, matching: searchText).map(\.locationID)
  }

  @Test("an exact identifier outranks a name match, which outranks a city match")
  func matchKindOrdering() {
    let airports = [
      Self.airport(locationID: "CCR", name: "Buchanan Field", city: "Oakland Hills"),
      Self.airport(locationID: "OAK", name: "Metropolitan", city: "Alameda"),
      Self.airport(locationID: "HWD", name: "Oakland South", city: "Hayward")
    ]

    #expect(Self.ranked(airports, matching: "OAK") == ["OAK", "HWD", "CCR"])
  }

  @Test("an exact ICAO identifier ranks alongside an exact location identifier")
  func ICAO_IDMatchesRankWithLocationID() {
    let airports = [
      Self.airport(locationID: "ZZZ", name: "Bravo Field", city: "Nowhere"),
      Self.airport(locationID: "AAA", ICAO_ID: "KSQL", name: "Alpha Field", city: "Nowhere")
    ]

    #expect(Self.ranked(airports, matching: "KSQL").first == "AAA")
  }

  @Test("identifier matching ignores case but demands the whole identifier")
  func identifierMatchIsExact() {
    let airport = Self.airport(locationID: "SQL", name: "San Carlos", city: "San Carlos")

    #expect(Airport.relevanceScore(for: airport, searchText: "sql") == 3)
    #expect(Airport.relevanceScore(for: airport, searchText: "SQ") < 3)
  }

  @Test("an airport matching nothing scores zero")
  func noMatchScoresZero() {
    let airport = Self.airport(locationID: "SQL", name: "San Carlos", city: "San Carlos")

    #expect(Airport.relevanceScore(for: airport, searchText: "Teterboro") == 0)
  }

  @Test(
    "two name matches are separated by how much of the name the text covers, not alphabetically"
  )
  func similarityBreaksTiesBeforeName() {
    let airports = [
      Self.airport(locationID: "AAA", name: "Metro Oakland Airport", city: "Alameda"),
      Self.airport(locationID: "OAK", name: "Oakland Intl", city: "Oakland")
    ]

    #expect(Self.ranked(airports, matching: "Oakland") == ["OAK", "AAA"])
  }
}
