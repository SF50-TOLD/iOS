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
/// Free-text matching mirrors the app's own airport picker: both fetch with
/// `Airport.searchPredicate(matching:)` and order with `Airport.ranked(_:matching:)`, so an identifier
/// typed into Shortcuts ranks the way it does in the app.
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
    let matches = try context.fetch(descriptor)
    return Airport.ranked(matches, matching: string).map(AirportEntity.init(from:))
  }

  /// The airports the app already has selected, takeoff first, so the common case needs no typing.
  ///
  /// Favorites and recents are deliberately not offered: uniquely among the app's settings they are
  /// stored outside the app group, so an extension resolving this query cannot read them.
  ///
  /// The leg order is restored afterwards because ``entities(for:)`` answers in whatever order the
  /// fetch returns. A list that put the destination above home base on some launches and below it on
  /// others would be the editor rearranging itself for no reason the reader can see.
  public func suggestedEntities() async throws -> [AirportEntity] {
    let selected = Self.selectedAirportRecordIDs()
    guard !selected.isEmpty else { return [] }
    let found = try await entities(for: selected)
    return selected.compactMap { recordID in found.first { $0.id == recordID } }
  }
  // swiftlint:enable async_without_await
}

extension AirportEntityQuery {
  /// The airports the app has selected, takeoff first, without repeating one selected for both legs.
  private static func selectedAirportRecordIDs() -> [String] {
    [Defaults[.takeoffAirport], Defaults[.landingAirport]]
      .compactMap(\.self)
      .reduce(into: []) { unique, recordID in
        guard !unique.contains(recordID) else { return }
        unique.append(recordID)
      }
  }
}
