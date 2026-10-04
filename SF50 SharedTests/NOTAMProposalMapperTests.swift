import Foundation
import NOTAMParsing
import Testing

@testable import SF50_Shared

/// The mapper decides what a formatted report proposes for a runway direction; these pin the rules
/// that turn surface conditions and obstacles into the values the pilot is asked to confirm.
struct `NOTAM proposal mapping` {
  /// Runway 09/27, true headings 090° and 270°, with both ends at 500 ft.
  private static let
    runway09 = runway("9", reciprocal: "27", trueHeadingDegrees: 90),
    runway27 = runway("27", reciprocal: "9", trueHeadingDegrees: 270)

  private static func runway(_ name: String, reciprocal: String, trueHeadingDegrees: Double)
    -> ProposalRunway
  {
    .init(
      name: name,
      reciprocalName: reciprocal,
      trueHeadingDegrees: trueHeadingDegrees,
      departureEndElevation: .init(value: 500, unit: .feet)
    )
  }

  private static func surface(
    _ runway: String,
    rwyCC: [Int]? = nil,
    contaminants: [FormattedReport.Contaminant] = []
  ) -> FormattedReport {
    .init(effects: [
      .init(runway: runway, surfaceCondition: .init(rwyCC: rwyCC, contaminants: contaminants))
    ])
  }

  /// An obstacle 120 ft above ground, 1 NM from `runwayEnd` in `direction`.
  private static func obstacle(
    _ direction: FormattedReport.CompassPoint,
    of runwayEnd: FormattedReport.RunwayEnd?,
    heightAGL: Double? = 120,
    heightMSL: Double? = nil
  ) -> FormattedReport {
    .init(effects: [
      .init(
        runway: runwayEnd?.runway,
        obstacle: .init(
          heightAGL: heightAGL.map { .init(value: $0, unit: .feet) },
          heightMSL: heightMSL.map { .init(value: $0, unit: .feet) },
          distance: .init(value: 1, unit: .nauticalMiles),
          distanceReference: "",
          direction: direction,
          runwayEnd: runwayEnd
        )
      )
    ])
  }

  /// The same contaminant on each third of a runway.
  private static func everyThird(_ type: FormattedReport.ContaminantType, coveragePercent: Int)
    -> [FormattedReport.Contaminant]
  {
    (1...3).map { .init(type: type, runwayThird: $0, coveragePercent: coveragePercent, depth: nil) }
  }

  private static func proposal(_ report: FormattedReport, for runway: ProposalRunway = runway09)
    -> NOTAMProposal
  {
    NOTAMProposalMapper.proposal(from: report, notamID: "A1/26", for: runway)
  }

  private static func notam(_ id: Int, _ text: String) -> NOTAMResponse {
    .init(
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
  func `proposes the lowest runway condition code reported`() {
    let report = Self.surface("09", rwyCC: [5, 3, 4])
    #expect(Self.proposal(report).contamination.map(\.value) == [.rwyCC(3)])
  }

  @Test
  func `proposes the worst contaminant category without condition codes`() {
    let report = Self.surface(
      "09",
      contaminants: [
        .init(type: .wet, runwayThird: nil, coveragePercent: 100, depth: nil),
        .init(
          type: .water,
          runwayThird: nil,
          coveragePercent: 50,
          depth: .init(value: 0.25, unit: .inches)
        ),
        .init(
          type: .slush,
          runwayThird: nil,
          coveragePercent: 25,
          depth: .init(value: 0.125, unit: .inches)
        )
      ]
    )
    #expect(
      Self.proposal(report).contamination.map(\.value)
        == [.waterOrSlush(depth: .init(value: 0.25, unit: .inches))]
    )
  }

  @Test(arguments: [
    // A third with nil braking.
    surface("09", rwyCC: [1, 0, 1], contaminants: everyThird(.ice, coveragePercent: 100)),
    // Too little contamination to earn codes.
    surface(
      "09",
      contaminants: [.init(type: .wet, runwayThird: nil, coveragePercent: 10, depth: nil)]
    ),
    surface(
      "09",
      contaminants: [.init(type: .wet, runwayThird: 1, coveragePercent: 60, depth: nil)]
    ),
    // A contaminant in no AFM category beside one in a category.
    surface(
      "09",
      contaminants: [
        .init(type: .wet, runwayThird: nil, coveragePercent: 50, depth: nil),
        .init(type: .frost, runwayThird: nil, coveragePercent: 50, depth: nil)
      ]
    )
  ])
  func `proposes no contamination the AFM gives no figures for`(_ report: FormattedReport) {
    #expect(Self.proposal(report).isEmpty)
  }

  @Test
  func `proposes for both directions of a runway pair`() {
    let report = Self.surface("09/27", rwyCC: [2, 2, 2])
    #expect(Self.proposal(report, for: Self.runway27).contamination.map(\.value) == [.rwyCC(2)])
    #expect(
      Self.proposal(
        report,
        for: Self.runway("9L", reciprocal: "27R", trueHeadingDegrees: 90)
      ).isEmpty
    )
  }

  @Test(arguments: [
    FormattedReport.RunwayEnd(runway: "09", end: .departure),
    FormattedReport.RunwayEnd(runway: "27", end: .approach)
  ])
  func `proposes an obstacle off the end a takeoff leaves from`(
    _ runwayEnd: FormattedReport.RunwayEnd
  ) {
    let report = Self.obstacle(.E, of: runwayEnd)
    #expect(
      Self.proposal(report).obstacle.map(\.value) == [
        .init(
          height: .init(value: 120, unit: .feet),
          distance: .init(value: 1, unit: .nauticalMiles)
        )
      ]
    )
    #expect(Self.proposal(report, for: Self.runway27).isEmpty)
  }

  @Test(arguments: [
    (FormattedReport.CompassPoint.ENE, true), (.ESE, true), (.NE, false), (.SE, false), (.W, false)
  ])
  func `proposes an obstacle only within a compass point of the takeoff's heading`(
    _ direction: FormattedReport.CompassPoint,
    _ isProposed: Bool
  ) {
    let report = Self.obstacle(direction, of: .init(runway: "09", end: .departure))
    #expect(Self.proposal(report).obstacle.isEmpty == !isProposed)
  }

  @Test
  func `proposes nothing for an obstacle beside the runway end, as MSP's crane by 12L is`() {
    let runway30R = Self.runway("30R", reciprocal: "12L", trueHeadingDegrees: 298)
    let report = Self.obstacle(.SW, of: .init(runway: "12L", end: .approach))
    #expect(Self.proposal(report, for: runway30R).isEmpty)
  }

  @Test
  func `measures an obstacle's height from the departure end's elevation`() {
    let report = Self.obstacle(.E, of: .init(runway: "09", end: .departure), heightMSL: 650)
    #expect(Self.proposal(report).obstacle.map(\.value.height) == [.init(value: 150, unit: .feet)])
  }

  @Test(arguments: [
    obstacle(.E, of: nil),
    obstacle(.E, of: .init(runway: "09", end: .departure), heightAGL: nil),
    obstacle(.E, of: .init(runway: "09", end: .departure), heightMSL: 480)
  ])
  func `proposes nothing for an obstacle off no runway end, of unknown height, or below the runway`(
    _ report: FormattedReport
  ) {
    #expect(Self.proposal(report).isEmpty)
  }

  @Test
  func `joins NOTAMs that agree, keeps those that don't as alternatives, and skips the rest`() {
    let proposal = NOTAMProposal(
      notams: [
        Self.notam(1, "AAA RWY 09 FICON 3/3/3 100 PCT 1/8IN WATER OBS AT 2609260325."),
        Self.notam(2, "AAA RWY 09 FICON 3/3/3 100 PCT 1/8IN WATER OBS AT 2609260325."),
        Self.notam(3, "AAA RWY 09/27 FICON 5/5/5 100 PCT WET OBS AT 2609260325."),
        Self.notam(4, "RWY 09/27 CLSD")
      ],
      runway: Self.runway09
    )

    #expect(proposal.contamination.map(\.value) == [.rwyCC(3), .rwyCC(5)])
    #expect(proposal.contamination.first?.notamIDs == ["A1/26", "A2/26"])
  }
}
