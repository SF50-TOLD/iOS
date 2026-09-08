import Foundation
import SwiftData
import Testing

@testable import SF50_Shared

/// A NOTAM names its runway by airport record ID and designator rather than pointing at it, so that
/// nav data can be replaced whole without taking the pilot's entries with it. These cover the
/// lookup that replaces the relationship, and what happens when the name stops matching.
@Suite
struct `NOTAM Resolution` {
  /// An airport with two runways, inserted and saved so relationships are resolvable.
  private static func seeded() throws -> (ModelContext, Airport, [String: Runway]) {
    let context = ModelContext(try AppStore.makeInMemoryContainer())
    let airport = Airport(
      recordID: "TEST",
      locationID: "TEST",
      ICAO_ID: nil,
      name: "Test Airport",
      city: nil,
      dataSource: .NASR,
      latitude: .init(value: 0, unit: .degrees),
      longitude: .init(value: 0, unit: .degrees),
      elevation: .init(value: 0, unit: .feet),
      variation: .init(value: 0, unit: .degrees),
      timeZone: nil
    )
    context.insert(airport)

    var runways: [String: Runway] = [:]
    for name in ["28L", "10R"] {
      let runway = Runway(
        name: name,
        elevation: nil,
        trueHeading: .init(value: 280, unit: .degrees),
        gradient: nil,
        length: .init(value: 5000, unit: .feet),
        takeoffRun: nil,
        takeoffDistance: nil,
        landingDistance: nil,
        surfaceType: .paved,
        airport: airport
      )
      context.insert(runway)
      runways[name] = runway
    }
    try context.save()

    return (context, airport, runways)
  }

  @Test("a NOTAM resolves back to the runway it names")
  func resolvesByIdentifier() throws {
    let (context, _, runways) = try Self.seeded()
    let store = NOTAMStore(context: context)
    let runway = try #require(runways["28L"])

    let created = store.upsert(for: runway)
    try context.save()

    #expect(store.notam(for: runway) === created)
  }

  @Test("asking twice for a runway's NOTAM yields the same one")
  func upsertIsIdempotent() throws {
    let (context, _, runways) = try Self.seeded()
    let store = NOTAMStore(context: context)
    let runway = try #require(runways["28L"])

    let first = store.upsert(for: runway)
    try context.save()
    let second = store.upsert(for: runway)

    #expect(first === second)
    #expect(try context.fetchCount(FetchDescriptor<NOTAM>()) == 1)
  }

  @Test("a NOTAM on one runway is not shown on another")
  func doesNotLeakBetweenRunways() throws {
    let (context, _, runways) = try Self.seeded()
    let store = NOTAMStore(context: context)
    let annotated = try #require(runways["28L"])
    let other = try #require(runways["10R"])

    _ = store.upsert(for: annotated)
    try context.save()

    #expect(store.notam(for: other) == nil)
  }

  /// Magnetic drift renames a runway, and the pilot must then see no NOTAM rather than one written
  /// against a designator that has moved.
  @Test("a renamed runway shows no NOTAM")
  func renamedRunwayDegradesToNothing() throws {
    let (context, _, runways) = try Self.seeded()
    let store = NOTAMStore(context: context)
    let runway = try #require(runways["28L"])

    _ = store.upsert(for: runway)
    try context.save()

    runway.name = "27L"
    try context.save()

    #expect(store.notam(for: runway) == nil)
  }

  @Test("an airport's NOTAMs come back keyed by runway")
  func resolvesWholeAirportAtOnce() throws {
    let (context, airport, runways) = try Self.seeded()
    let store = NOTAMStore(context: context)
    for runway in runways.values { _ = store.upsert(for: runway) }
    try context.save()

    let notams = store.notams(at: airport)

    #expect(Set(notams.keys) == ["28L", "10R"])
  }
}
