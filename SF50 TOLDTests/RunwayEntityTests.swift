import Foundation
import Testing

@testable import SF50_TOLD

/// A runway has no identifier of its own — SwiftData identifies one by its airport and its name — so
/// ``RunwayEntity`` synthesizes a composite. Shortcuts people have already built are stored against
/// these strings, so the split has to survive every identifier the nav database actually contains.
@Suite
struct `Runway Entity Identity` {
  @Test(
    arguments: [
      (airport: "SQL", runway: "30"),
      (airport: "OAK", runway: "28L"),
      (airport: "1C9", runway: "9"),
      (airport: "00CA", runway: "18")
    ] as [(airport: String, runway: String)]
  )
  func identifiersRoundTrip(airport: String, runway: String) throws {
    let identifier = RunwayEntity.identifier(airportRecordID: airport, name: runway)
    let components = try #require(RunwayEntity.components(of: identifier))

    #expect(components.airportRecordID == airport)
    #expect(components.name == runway)
  }

  /// OurAirports record IDs are not guaranteed to be bare identifiers, and a slash inside one would
  /// break a naive split. Runway designators never contain a slash, so the split takes the last one.
  @Test("a record ID containing a slash still round-trips")
  func recordIDWithSeparatorRoundTrips() throws {
    let identifier = RunwayEntity.identifier(airportRecordID: "US/0A7", name: "12")
    let components = try #require(RunwayEntity.components(of: identifier))

    #expect(components.airportRecordID == "US/0A7")
    #expect(components.name == "12")
  }

  @Test(arguments: ["", "SQL", "/30", "SQL/"])
  func malformedIdentifiersAreRejected(identifier: String) {
    #expect(RunwayEntity.components(of: identifier) == nil)
  }
}
