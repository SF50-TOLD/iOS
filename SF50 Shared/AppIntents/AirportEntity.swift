public import AppIntents
import Defaults
import SwiftData

/// An airport, as the system's intent surfaces see it.
///
/// Shortcuts, Siri, Spotlight and the widget configuration editor all resolve an airport through this
/// type. It is a `Sendable` copy keyed on `Airport.recordID` rather than the SwiftData model, which
/// cannot leave the context that fetched it.
public struct AirportEntity: AppEntity {
  public static var typeDisplayRepresentation: TypeDisplayRepresentation { "Airport" }

  public static var defaultQuery: AirportEntityQuery { .init() }

  /// The airport's `recordID`.
  public let id: String

  /// The identifier the app shows for this airport.
  public let displayID: String

  /// The airport's name.
  public let name: String

  /// The city the airport serves, when known.
  public let city: String?

  public var displayRepresentation: DisplayRepresentation {
    .init(
      title: "\(displayID)",
      subtitle: city.map { "\(name) — \($0)" } ?? "\(name)"
    )
  }

  /// Copies the identifying facts out of a SwiftData airport.
  ///
  /// - Parameter airport: The airport to represent.
  public init(from airport: Airport) {
    id = airport.recordID
    displayID = airport.displayID
    name = airport.name
    city = airport.city
  }
}

/// Resolves ``AirportEntity`` values for the system's intent surfaces.
///
/// Free-text matching mirrors the app's own airport picker: both go through
/// `Airport.searchPredicate(matching:)` and `Airport.relevanceScore(for:searchText:)`, so an
/// identifier typed into Shortcuts ranks the way it does in the app.
public struct AirportEntityQuery: EntityStringQuery {
  public init() {}

  // `EntityQuery` declares these `async`; the fetch itself is synchronous.
  // swiftlint:disable async_without_await

  public func entities(for identifiers: [String]) async throws -> [AirportEntity] {
    let context = ModelContext(AppGroupStore.container)
    let descriptor = FetchDescriptor<Airport>(
      predicate: #Predicate { identifiers.contains($0.recordID) }
    )
    return try context.fetch(descriptor).map(AirportEntity.init(from:))
  }

  public func entities(matching string: String) async throws -> [AirportEntity] {
    let context = ModelContext(AppGroupStore.container)
    let descriptor = FetchDescriptor<Airport>(predicate: Airport.searchPredicate(matching: string))
    return try context.fetch(descriptor)
      .map { (airport: $0, relevance: Airport.relevanceScore(for: $0, searchText: string)) }
      .sorted { left, right in
        if left.relevance != right.relevance { return left.relevance > right.relevance }
        return left.airport.name.localizedStandardCompare(right.airport.name) == .orderedAscending
      }
      .prefix(Airport.searchResultLimit)
      .map { AirportEntity(from: $0.airport) }
  }

  /// The airports the app already has selected, so the common case needs no typing.
  ///
  /// Favorites and recents are deliberately not offered: uniquely among the app's settings they are
  /// stored outside the app group, so an extension resolving this query cannot read them.
  public func suggestedEntities() async throws -> [AirportEntity] {
    let selected = [Defaults[.takeoffAirport], Defaults[.landingAirport]].compactMap(\.self)
    guard !selected.isEmpty else { return [] }
    return try await entities(for: Array(Set(selected)))
  }
  // swiftlint:enable async_without_await
}
