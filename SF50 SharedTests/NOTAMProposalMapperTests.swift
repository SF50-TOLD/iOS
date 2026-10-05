import Foundation
import NOTAMModel
import NOTAMParsing
import Testing

@testable import SF50_Shared

/// The mapper decides what a NOTAM's reading proposes for a runway direction; these pin the rules
/// that turn distances, ends and surface reports into the values the pilot is asked to confirm.
struct `NOTAM proposal mapping` {
  // Runway 09/27: 6,000 ft long, both ends at 500 ft, published TORA and LDA the full length.
  private static let runway09 = ProposalRunway(
    name: "9",
    reciprocalName: "27",
    trueHeadingDegrees: 90,
    departureEndElevation: feet(500),
    publishedTakeoffRun: feet(6000),
    publishedLandingDistance: feet(6000)
  )
  private static let runway27 = ProposalRunway(
    name: "27",
    reciprocalName: "9",
    trueHeadingDegrees: 270,
    departureEndElevation: feet(500),
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

  /// A parsed obstacle 120 ft above ground, 1 NM from `runwayEnd` in `direction`.
  private static func obstacleReading(
    _ direction: FormattedReport.CompassPoint,
    of runwayEnd: FormattedReport.RunwayEnd,
    heightMSL: Double? = nil
  ) -> NOTAMExtractor.Reading {
    let report = FormattedReport(effects: [
      .init(
        runway: runwayEnd.runway,
        obstacle: .init(
          heightAGL: Self.feet(120),
          heightMSL: heightMSL.map(Self.feet),
          distance: .init(value: 1, unit: .nauticalMiles),
          distanceReference: "",
          direction: direction,
          runwayEnd: runwayEnd
        )
      )
    ])
    return .init(extraction: NOTAMExtraction(report), source: .parser, report: report)
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
  func `applies a partial closure to each direction, placing a compass end from each`() {
    let closedPortion = NOTAMExtraction.PartialClosure(length: Self.length(1000), end: "W")
    let reading = Self.parsed(
      .init(runway: "09", closure: .none, partialClosure: closedPortion),
      .init(runway: "27", closure: .none, partialClosure: closedPortion)
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
      .init(type: .wet, coveragePercent: 100, depth: nil),
      .init(
        type: .water,
        coveragePercent: 50,
        depth: .init(value: 0.25, unit: .in)
      ),
      .init(
        type: .slush,
        coveragePercent: 25,
        depth: .init(value: 0.125, unit: .in)
      )
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

  @Test(arguments: [
    // A third with nil braking.
    NOTAMExtraction.SurfaceCondition(
      rwyCC: [1, 0, 1],
      contaminants: [.init(type: .ice, coveragePercent: 100, depth: nil)]
    ),
    // Too little contamination to earn codes.
    .init(
      rwyCC: nil,
      contaminants: [.init(type: .wet, coveragePercent: 10, depth: nil)]
    ),
    // A contaminant in no AFM category beside one in a category.
    .init(
      rwyCC: nil,
      contaminants: [
        .init(type: .wet, coveragePercent: 50, depth: nil),
        .init(type: .frost, coveragePercent: 50, depth: nil)
      ]
    )
  ])
  func `proposes no contamination the AFM gives no figures for`(
    _ condition: NOTAMExtraction.SurfaceCondition
  ) {
    let reading = Self.parsed(.init(runway: "09", closure: .none, surfaceCondition: condition))
    #expect(Self.proposal(reading, for: Self.runway09).isEmpty)
  }

  @Test
  func `proposes a model reading's fields only when its manifest lists them`() {
    let effect = NOTAMExtraction.RunwayEffect(
      runway: "09",
      closure: .none,
      partialClosure: .init(length: Self.length(1000), end: nil)
    )
    let obstacle = NOTAMExtraction.Obstacle(
      height: .init(value: 120, unit: .ft, datum: .AGL),
      distance: .init(value: 1, unit: .nm),
      reference: .init(kind: .departureEnd, runway: "09"),
      direction: .compass(.E)
    )
    let reading = NOTAMExtractor.Reading(
      extraction: .init(isCanceled: false, effects: [effect], obstacles: [obstacle]),
      source: .model(version: "test")
    )

    #expect(Self.proposal(reading.limited(to: []), for: Self.runway09).isEmpty)
    let proposal = Self.proposal(
      reading.limited(to: [.closedLength, .obstacleHeight]),
      for: Self.runway09
    )
    #expect(proposal.takeoffShortening.map(\.value) == [Self.feet(1000)])
    #expect(proposal.obstacle.isEmpty, "A model reading's obstacles propose nothing")
  }

  @Test(arguments: [
    (FormattedReport.CompassPoint.E, FormattedReport.RunwayEnd(runway: "27", end: .approach), true),
    (.ENE, .init(runway: "09", end: .departure), true),
    (.NE, .init(runway: "09", end: .departure), false),
    (.E, .init(runway: "09", end: .approach), false)
  ])
  func `proposes a parsed obstacle off the end a takeoff leaves from, toward its heading`(
    _ direction: FormattedReport.CompassPoint,
    _ runwayEnd: FormattedReport.RunwayEnd,
    _ isProposed: Bool
  ) {
    let reading = Self.obstacleReading(direction, of: runwayEnd)
    let expected: [ProposedObstacle] =
      isProposed
      ? [.init(height: Self.feet(120), distance: .init(value: 1, unit: .nauticalMiles))] : []
    #expect(Self.proposal(reading, for: Self.runway09).obstacle.map(\.value) == expected)
  }

  @Test(arguments: [(650.0, 150.0), (480, nil)])
  func `measures a parsed obstacle's height from the departure end's elevation`(
    _ heightMSL: Double,
    _ expectedHeight: Double?
  ) {
    let reading = Self.obstacleReading(
      .E,
      of: .init(runway: "09", end: .departure),
      heightMSL: heightMSL
    )
    #expect(
      Self.proposal(reading, for: Self.runway09).obstacle.map(\.value.height)
        == (expectedHeight.map { [Self.feet($0)] } ?? [])
    )
  }

  @Test
  func `proposes nothing from a cancellation or an effect naming no runway`() {
    let cancelled = NOTAMExtractor.Reading(
      extraction: .init(isCanceled: true, effects: [.init(runway: "09", closure: .both)]),
      source: .parser
    )
    let aerodrome = Self.parsed(.init(runway: nil, closure: .both))

    #expect(Self.proposal(cancelled, for: Self.runway09).isEmpty)
    #expect(Self.proposal(aerodrome, for: Self.runway09).isEmpty)
  }

  @Test
  func `reports a closure for the operations it closes`() {
    let
      takeoff = Self.proposal(
        Self.parsed(.init(runway: "09", closure: .takeoff)),
        for: Self.runway09
      ),
      both = Self.proposal(Self.parsed(.init(runway: "09", closure: .both)), for: Self.runway09)

    #expect(takeoff.closedForTakeoffBy.map(\.notamID) == ["A1/26"])
    #expect(takeoff.closedForLandingBy.isEmpty)
    #expect(both.closedForLandingBy.map(\.notamID) == ["A1/26"])
  }

  @Test
  func `joins NOTAMs that agree and keeps those that don't as alternatives`() {
    let
      first = Self.parsed(
        .init(
          runway: "09",
          closure: .none,
          declaredDistances: .init(TORA: Self.length(5000), LDA: nil)
        )
      ),
      second = Self.parsed(
        .init(
          runway: "09",
          closure: .none,
          declaredDistances: .init(TORA: Self.length(5500), LDA: nil)
        )
      )
    var proposal = NOTAMProposalMapper.proposal(from: first, notamID: "A1/26", for: Self.runway09)
    proposal.merge(NOTAMProposalMapper.proposal(from: first, notamID: "A2/26", for: Self.runway09))
    proposal.merge(NOTAMProposalMapper.proposal(from: second, notamID: "A3/26", for: Self.runway09))

    #expect(proposal.takeoffShortening.map(\.value) == [Self.feet(1000), Self.feet(500)])
    #expect(proposal.takeoffShortening.first?.sources.map(\.notamID) == ["A1/26", "A2/26"])
  }
}
