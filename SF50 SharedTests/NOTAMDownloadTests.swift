import Foundation
import Testing

@testable import SF50_Shared

/// The NOTAM service files an airport's NOTAMs under both its FAA and its ICAO identifier, with none
/// in common, so the download asks for both and combines what comes back.
struct `NOTAM download` {
  private static func notam(_ id: Int, at location: String) -> NOTAMResponse {
    NOTAMResponse(
      id: id,
      notamId: "A\(id)/26",
      icaoLocation: location,
      effectiveStart: .distantPast,
      effectiveEnd: nil,
      schedule: nil,
      notamText: "RWY 09 CLSD",
      qLine: nil,
      purpose: nil,
      scope: nil,
      trafficType: nil
    )
  }

  @Test
  func `combines the NOTAMs filed under each identifier, once each`() async throws {
    let loader = StubLoader(byIdentifier: [
      "DEN": [Self.notam(1, at: "DEN")],
      "KDEN": [Self.notam(2, at: "KDEN"), Self.notam(1, at: "DEN")]
    ])

    let notams = try await BasePerformanceViewModel.downloadNOTAMs(
      for: ["DEN", "KDEN"],
      from: nil,
      to: nil,
      using: loader
    )

    #expect(Set(notams.map(\.id)) == [1, 2])
    #expect(notams.count == 2)
  }

  @Test
  func `shows what one identifier returned when the other fails, and fails only when both do`()
    async throws
  {
    let loader = StubLoader(byIdentifier: ["DEN": [Self.notam(1, at: "DEN")]])

    let notams = try await BasePerformanceViewModel.downloadNOTAMs(
      for: ["DEN", "KDEN"],
      from: nil,
      to: nil,
      using: loader
    )
    #expect(notams.map(\.id) == [1])

    await #expect(throws: URLError.self) {
      try await BasePerformanceViewModel.downloadNOTAMs(
        for: ["KDEN"],
        from: nil,
        to: nil,
        using: loader
      )
    }
  }
}

/// Returns the NOTAMs it holds for an identifier, and fails for any it doesn't.
private actor StubLoader: NOTAMLoaderProtocol {
  let byIdentifier: [String: [NOTAMResponse]]

  init(byIdentifier: [String: [NOTAMResponse]]) {
    self.byIdentifier = byIdentifier
  }

  func fetchNOTAMs(for icao: String, startDate _: Date?, endDate _: Date?) throws -> [NOTAMResponse]
  {
    guard let notams = byIdentifier[icao] else { throw URLError(.badServerResponse) }
    return notams
  }
}
