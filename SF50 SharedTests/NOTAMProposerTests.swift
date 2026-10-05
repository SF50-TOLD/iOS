import Foundation
import NOTAMModel
import Synchronization
import Testing

@testable import SF50_Shared

/// The proposer reads each NOTAM once per model and gathers what they propose per runway; these
/// cover the reading cache and what happens when the model can't read a NOTAM.
struct `NOTAM proposer` {
  private static let runway = ProposalRunway(
    name: "9",
    reciprocalName: "27",
    trueHeadingDegrees: 90,
    departureEndElevation: .init(value: 0, unit: .feet),
    publishedTakeoffRun: .init(value: 6000, unit: .feet),
    publishedLandingDistance: .init(value: 6000, unit: .feet)
  )

  private static func notam(_ id: Int, _ text: String) -> NOTAMResponse {
    NOTAMResponse(
      id: id,
      notamId: "A\(id)/26",
      icaoLocation: "KAAA",
      effectiveStart: .distantPast,
      effectiveEnd: nil,
      schedule: nil,
      notamText: text,
      qLine: nil,
      purpose: nil,
      scope: nil,
      trafficType: nil
    )
  }

  @Test
  func `reads each NOTAM once, and proposes only the fields the model cleared`() async {
    let reader = StubReader(fields: [.closedLength])
    let proposer = NOTAMProposer { reader }
    let notams = [
      Self.notam(1, "RWY 09 FIRST 1000FT CLSD"), Self.notam(2, "RWY 09 FIRST 1000FT CLSD")
    ]

    _ = await proposer.proposals(for: notams, runways: [Self.runway])
    let proposals = await proposer.proposals(for: notams, runways: [Self.runway])

    #expect(reader.readCount == 2)
    let proposal = proposals.byRunway["9"]
    #expect(proposal?.takeoffShortening.first?.sources.map(\.notamID) == ["A1/26", "A2/26"])
    #expect(proposal?.takeoffShorteningLocation.isEmpty == true)
  }

  @Test
  func `records a NOTAM the model can't read, and reads formatted reports without a model`() async {
    let proposer = NOTAMProposer { nil }
    let proposals = await proposer.proposals(
      for: [Self.notam(1, "RWY 09 FIRST 1000FT CLSD")],
      runways: [Self.runway]
    )

    #expect(proposals.byRunway["9"]?.isEmpty == true)
    guard case .modelUnavailable = proposals.unreadable["A1/26"] else {
      Issue.record("expected the model to be unavailable")
      return
    }
  }
}

/// Reads every NOTAM as a 1,000 ft partial closure of runway 09's first end, and counts reads.
private final class StubReader: NOTAMReader {
  let proposableFields: Set<ProposableField>
  let modelVersion = "stub"
  private let reads = Mutex(0)

  var readCount: Int { reads.withLock { $0 } }

  init(fields: Set<ProposableField>) {
    proposableFields = fields
  }

  func read(notamText _: String, location _: String) throws(NOTAMReadFailure)
    -> NOTAMExtraction
  {
    reads.withLock { $0 += 1 }
    return .init(
      isCanceled: false,
      effects: [
        .init(
          runway: "09",
          closure: .none,
          partialClosure: .init(length: .init(value: 1000, unit: .ft), end: "thresholdEnd")
        )
      ]
    )
  }
}
