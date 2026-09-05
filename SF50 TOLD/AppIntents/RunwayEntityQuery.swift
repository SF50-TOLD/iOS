import AppIntents
import Defaults
import Foundation
import SF50_Shared
import SwiftData

/// Resolves ``RunwayEntity`` values.
///
/// A runway designator only means something at an airport — half the country has a runway 27 — so
/// suggestions are scoped to whichever airport the intent has already resolved, read through a
/// parameter dependency. Resolving a *stored* identifier is different: a shortcut saved months ago
/// names its own airport, and honoring that is what keeps it working after the app's selection moves
/// on, so ``entities(for:)`` decodes the airport out of each identifier instead.
struct RunwayEntityQuery: EntityStringQuery {
  @IntentParameterDependency<RunwayNumbersIntent>(\.$airport, \.$operation)
  var context

  func entities(for identifiers: [String]) async throws -> [RunwayEntity] {
    let requested = identifiers.compactMap(RunwayEntity.components(of:))
    return try await runways(named: requested)
  }

  func entities(matching string: String) async throws -> [RunwayEntity] {
    try await allRunways().filter { $0.name.localizedCaseInsensitiveContains(string) }
  }

  func suggestedEntities() async throws -> [RunwayEntity] {
    try await allRunways()
  }
}

extension RunwayEntityQuery {
  private var selectionKey: Defaults.Key<String?> {
    switch context?.operation ?? .takeoff {
      case .takeoff: .takeoffAirport
      case .landing: .landingAirport
    }
  }

  /// Every runway at the airport this intent is working with.
  ///
  /// Isolated to the main actor so the store is reached from one place; the hop is what makes the
  /// query's `async` requirements meaningful rather than decorative.
  @MainActor
  private func allRunways() throws -> [RunwayEntity] {
    let recordID = context?.airport.id ?? Defaults[selectionKey],
      modelContext = ModelContext(AppGroupStore.container)
    guard let recordID,
      let airport = try findAirport(for: recordID, in: modelContext)
    else { return [] }
    return entities(at: airport)
  }

  /// Resolves stored identifiers, each against the airport it names.
  @MainActor
  private func runways(named requested: [(airportRecordID: String, name: String)]) throws
    -> [RunwayEntity]
  {
    let modelContext = ModelContext(AppGroupStore.container),
      wanted = Dictionary(
        grouping: requested,
        by: \.airportRecordID
      )
      .mapValues { Set($0.map(\.name)) }

    return try wanted.flatMap { recordID, names -> [RunwayEntity] in
      guard let airport = try findAirport(for: recordID, in: modelContext) else { return [] }
      return entities(at: airport).filter { names.contains($0.name) }
    }
  }

  @MainActor
  private func entities(at airport: Airport) -> [RunwayEntity] {
    airport.runways
      .sorted(using: Runway.NameComparator())
      .map { runway in
        RunwayEntity(
          airportRecordID: airport.recordID,
          airportDisplayID: airport.displayID,
          name: runway.name
        )
      }
  }
}
