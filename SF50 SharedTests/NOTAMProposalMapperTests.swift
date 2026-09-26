import Foundation
import NOTAMModel
import Testing

@testable import SF50_Shared

/// The mapper decides what a NOTAM's reading proposes for a runway direction; these pin the rules
/// that turn distances, ends and surface reports into the values the pilot is asked to confirm.
struct `NOTAM proposal mapping` {
  // Runway 09/27: 6,000 ft long, published TORA and LDA the full length.
  private static let runway09 = ProposalRunway(
    name: "9",
    reciprocalName: "27",
    trueHeadingDegrees: 90,
    publishedTakeoffRun: feet(6000),
    publishedLandingDistance: feet(6000)
  )
  private static let runway27 = ProposalRunway(
    name: "27",
    reciprocalName: "9",
    trueHeadingDegrees: 270,
    publishedTakeoffRun: feet(6000),
    publishedLandingDistance: feet(5800),
    publishedDisplacement: feet(200)
  )

  private static func feet(_ value: Double) -> Measurement<UnitLength> {
    .init(value: value, unit: .feet)
  }

  private static func length(_ value: Double, _ unit: NOTAMExtraction.LengthUnit = .ft)
    -> NOTAMExtraction.Length
  {
    .init(value: value, unit: unit)
  }

  private static func parsed(_ effects: NOTAMExtraction.RunwayEffect...) -> NOTAMExtractor.Reading {
    .init(extraction: .init(isCanceled: false, effects: effects), source: .parser)
  }

  private static func proposal(_ reading: NOTAMExtractor.Reading, for runway: ProposalRunway)
    -> NOTAMProposal
  {
    NOTAMProposalMapper.proposal(from: reading, notamID: "A1/26", for: runway)
  }

  @Test
  func `shortens by the difference from the published declared distances`() throws {
    let reading = Self.parsed(
      .init(
        runway: "27",
        closure: .none,
        declaredDistances: .init(
          TORA: Self.length(5000),
          TODA: nil,
          ASDA: nil,
          LDA: Self.length(1524, .m)
        )
      )
    )
    let proposal = Self.proposal(reading, for: Self.runway27)

    #expect(proposal.takeoffShortening.map(\.value) == [Self.feet(1000)])
    let landing = try #require(proposal.landingShortening.first?.value)
    #expect(abs(landing.converted(to: .feet).value - 800) < 0.1)
    #expect(Self.proposal(reading, for: Self.runway09).isEmpty)
  }

  @Test
  func `applies a pair's partial closure to both directions, placing FIRST from each`() {
    let reading = Self.parsed(
      .init(runway: "09/27", closure: .partial, closedLength: Self.length(1000), closedEnd: "W")
    )
    let on09 = Self.proposal(reading, for: Self.runway09),
      on27 = Self.proposal(reading, for: Self.runway27)

    #expect(on09.takeoffShortening.map(\.value) == [Self.feet(1000)])
    #expect(on09.landingShortening.map(\.value) == [Self.feet(1000)])
    #expect(on09.takeoffShorteningLocation.map(\.value) == [.thresholdEnd])
    #expect(on27.takeoffShorteningLocation.map(\.value) == [.departureEnd])
  }

  @Test(arguments: [
    ("thresholdEnd", ShorteningLocation.thresholdEnd, ShorteningLocation.departureEnd),
    ("departureEnd", .departureEnd, .thresholdEnd),
    ("09", .thresholdEnd, .departureEnd),
    ("27", .departureEnd, .thresholdEnd)
  ])
  func `places a closed end relative to each direction`(
    _ closedEnd: String,
    _ on09: ShorteningLocation,
    _ on27: ShorteningLocation
  ) {
    #expect(
      NOTAMProposalMapper.location(ofClosedEnd: closedEnd, effectRunway: "09", on: Self.runway09)
        == on09
    )
    #expect(
      NOTAMProposalMapper.location(ofClosedEnd: closedEnd, effectRunway: "09", on: Self.runway27)
        == on27
    )
  }

  @Test
  func `doesn't place FIRST on a pair, or a compass end across the runway`() {
    #expect(
      NOTAMProposalMapper.location(
        ofClosedEnd: "thresholdEnd",
        effectRunway: "09/27",
        on: Self.runway09
      ) == nil
    )
    #expect(
      NOTAMProposalMapper.location(ofClosedEnd: "N", effectRunway: "09/27", on: Self.runway09)
        == nil
    )
  }

  @Test
  func `shortens landing by a displacement beyond the published one`() {
    let reading = Self.parsed(
      .init(runway: "27", closure: .none, thresholdDisplacement: Self.length(500))
    )
    let proposal = Self.proposal(reading, for: Self.runway27)

    #expect(proposal.landingShortening.map(\.value) == [Self.feet(300)])
    #expect(proposal.landingShorteningLocation.map(\.value) == [.thresholdEnd])
    #expect(proposal.takeoffShortening.isEmpty)
  }

  @Test
  func `proposes the lowest runway condition code reported`() {
    let reading = Self.parsed(
      .init(
        runway: "09",
        closure: .none,
        surfaceCondition: .init(rwyCC: [5, 3, 4], contaminants: [])
      )
    )
    #expect(Self.proposal(reading, for: Self.runway09).contamination.map(\.value) == [.rwyCC(3)])
  }

  @Test
  func `proposes the worst contaminant category without condition codes`() {
    let contaminants: [NOTAMExtraction.Contaminant] = [
      .init(type: .wet, runwayThird: nil, coveragePercent: 100, depth: nil),
      .init(
        type: .water,
        runwayThird: nil,
        coveragePercent: 50,
        depth: .init(value: 0.25, unit: .in)
      ),
      .init(type: .slush, runwayThird: nil, coveragePercent: 25, depth: nil)
    ]
    let reading = Self.parsed(
      .init(
        runway: "09",
        closure: .none,
        surfaceCondition: .init(rwyCC: nil, contaminants: contaminants)
      )
    )
    #expect(
      Self.proposal(reading, for: Self.runway09).contamination.map(\.value)
        == [.waterOrSlush(depth: .init(value: 0.25, unit: .inches))]
    )
  }

  @Test
  func `proposes a model reading's fields only when its manifest lists them`() {
    let effect = NOTAMExtraction.RunwayEffect(
      runway: "09",
      closure: .partial,
      closedLength: Self.length(1000),
      obstacle: .init(heightAGL: Self.length(120))
    )
    let reading = NOTAMExtractor.Reading(
      extraction: .init(isCanceled: false, effects: [effect]),
      source: .model(version: "v7")
    )

    #expect(Self.proposal(reading.limited(to: []), for: Self.runway09).isEmpty)
    let proposal = Self.proposal(reading.limited(to: [.obstacleHeightAGL]), for: Self.runway09)
    #expect(proposal.takeoffShortening.isEmpty)
    #expect(proposal.obstacleHeight.map(\.value) == [Self.feet(120)])
  }

  @Test
  func `proposes nothing from a cancellation or an effect naming no runway`() {
    let cancelled = NOTAMExtractor.Reading(
      extraction: .init(isCanceled: true, effects: [.init(runway: "09", closure: .full)]),
      source: .parser
    )
    let aerodrome = Self.parsed(
      .init(runway: nil, closure: .none, obstacle: .init(heightAGL: Self.length(90)))
    )

    #expect(Self.proposal(cancelled, for: Self.runway09).isEmpty)
    #expect(Self.proposal(aerodrome, for: Self.runway09).isEmpty)
  }

  @Test
  func `joins NOTAMs that agree and keeps those that don't as alternatives`() {
    let
      first = Self.parsed(
        .init(
          runway: "09",
          closure: .none,
          declaredDistances: .init(TORA: Self.length(5000), TODA: nil, ASDA: nil, LDA: nil)
        )
      ),
      second = Self.parsed(
        .init(
          runway: "09",
          closure: .none,
          declaredDistances: .init(TORA: Self.length(5500), TODA: nil, ASDA: nil, LDA: nil)
        )
      )
    var proposal = NOTAMProposalMapper.proposal(from: first, notamID: "A1/26", for: Self.runway09)
    proposal.merge(NOTAMProposalMapper.proposal(from: first, notamID: "A2/26", for: Self.runway09))
    proposal.merge(NOTAMProposalMapper.proposal(from: second, notamID: "A3/26", for: Self.runway09))

    #expect(proposal.takeoffShortening.map(\.value) == [Self.feet(1000), Self.feet(500)])
    #expect(proposal.takeoffShortening.first?.sources.map(\.notamID) == ["A1/26", "A2/26"])
  }
}
