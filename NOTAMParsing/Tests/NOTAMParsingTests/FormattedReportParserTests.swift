import Foundation
import Testing

@testable import NOTAMParsing

struct `Formatted report parser` {
  private typealias Effect = FormattedReport.RunwayEffect
  private typealias Contaminant = FormattedReport.Contaminant

  private static func parse(notamText: String) -> FormattedReport? {
    FormattedReportParser().parse(notamText: notamText)
  }

  private static func inches(_ value: Double) -> Measurement<UnitLength> {
    .init(value: value, unit: .inches)
  }

  private static func feet(_ value: Double) -> Measurement<UnitLength> {
    .init(value: value, unit: .feet)
  }

  private static func surface(_ runway: String, _ rwyCC: [Int]?, _ contaminants: [Contaminant])
    -> Effect
  {
    .init(runway: runway, surfaceCondition: .init(rwyCC: rwyCC, contaminants: contaminants))
  }

  /// The same contaminant on each third of a runway.
  private static func everyThird(
    _ type: FormattedReport.ContaminantType,
    coveragePercent: Int,
    depth: Measurement<UnitLength>? = nil
  ) -> [Contaminant] {
    (1...3).map {
      .init(type: type, runwayThird: $0, coveragePercent: coveragePercent, depth: depth)
    }
  }

  @Test
  func `reads a FICON for the whole runway, skipping treatments`() {
    let report = Self.parse(
      notamText: "JNU RWY 08 FICON 5/5/5 100 PCT WET DEICED LIQUID OBS AT\n2511280227."
    )
    #expect(
      report
        == .init(effects: [
          Self.surface(
            "08",
            [5, 5, 5],
            [.init(type: .wet, runwayThird: nil, coveragePercent: 100, depth: nil)]
          )
        ])
    )
  }

  @Test
  func `reads a FICON by thirds, with layered contaminants and fractional depths`() {
    let report = Self.parse(
      notamText: """
        FAR RWY 31 FICON 6/3/3 10 PCT ICE AND 10 PCT COMPACTED SN, 10 PCT
        ICE AND 30 PCT 1/8IN DRY SN OVER COMPACTED SN, 10 PCT ICE AND 20 PCT
        COMPACTED SN OBS AT 2511280521.
        """
    )
    #expect(
      report
        == .init(effects: [
          Self.surface(
            "31",
            [6, 3, 3],
            [
              .init(type: .ice, runwayThird: 1, coveragePercent: 10, depth: nil),
              .init(type: .compactedSnow, runwayThird: 1, coveragePercent: 10, depth: nil),
              .init(type: .ice, runwayThird: 2, coveragePercent: 10, depth: nil),
              .init(
                type: .drySnowOverCompactedSnow,
                runwayThird: 2,
                coveragePercent: 30,
                depth: Self.inches(0.125)
              ),
              .init(type: .ice, runwayThird: 3, coveragePercent: 10, depth: nil),
              .init(type: .compactedSnow, runwayThird: 3, coveragePercent: 20, depth: nil)
            ]
          )
        ])
    )
  }

  @Test
  func `reads a FICON without codes, leaving out what lies beyond the cleared width`() {
    let swept = Self.parse(
      notamText: """
        GTF RWY 03 FICON 5/5/5 40 PCT 1/8IN DRY SN SWEPT 90FT WID
        REMAINDER 1/8IN DRY SN OBS AT 2511280533.
        """
    )
    let uncoded = Self.parse(
      notamText: "SLK RWY 23 FICON 10 PCT ICE 130FT WID OBS AT 2511250948."
    )
    #expect(
      swept?.effects.first?.surfaceCondition?.contaminants == [
        .init(type: .drySnow, runwayThird: nil, coveragePercent: 40, depth: Self.inches(0.125))
      ]
    )
    #expect(
      uncoded
        == .init(effects: [
          Self.surface(
            "23",
            nil,
            [.init(type: .ice, runwayThird: nil, coveragePercent: 10, depth: nil)]
          )
        ])
    )
  }

  @Test
  func `reads a SNOWTAM's runways, with depths in millimetres`() {
    let report = Self.parse(
      notamText: """
        SWEF2270 EFHK 09200214
        (SNOWTAM 2270
        EFHK
        09200214 04L 5/5/5 100/100/100 NR/NR/NR WET/WET/WET
        09200025 04R 5/4/3 100/100/100 NR/NR/NR WET/WET/WET

        REMARK/ RWY 04R SECOND PART RWYCC DOWNGRADED.)
        """
    )
    let snow = Self.parse(
      notamText: """
        SWBG0221 BGQQ 09241032
         (SNOWTAM 0221
         BGQQ
         09241032 16 5/5/5 100/100/100 03/03/03 DRY SNOW/DRY SNOW/DRY SNOW
         REMARK/ RWY 16 TAKEOFF SIGNIFICANT CONTAMINANT THIN RWYCC 5/5/5.)
        """
    )
    #expect(
      report
        == .init(effects: [
          Self.surface("04L", [5, 5, 5], Self.everyThird(.wet, coveragePercent: 100)),
          Self.surface("04R", [5, 4, 3], Self.everyThird(.wet, coveragePercent: 100))
        ])
    )
    #expect(
      snow?.effects.first?.surfaceCondition?.contaminants
        == Self.everyThird(
          .drySnow,
          coveragePercent: 100,
          depth: .init(value: 3, unit: .millimeters)
        )
    )
  }

  @Test
  func `reads an RSC's runways, skipping known remarks and the non-GRF section`() {
    let report = Self.parse(
      notamText: """
        RSC 16 3/2/5 50 PCT 1/8IN WET SNOW, 70 PCT 1/8IN WET SNOW, 40 PCT
        1/8IN WET SNOW. TOUCHDOWN RWYCC DOWNGRADED, CHEMICAL RESIDUE PRESENT.
        SWEEPING IN PROGRESS. VALID NOV 25 1124 - NOV 25 1924.

        RSC 34 5/2/3 100 PCT 1/8IN WET SNOW. VALID NOV 25 1124 - NOV 25 1924.

        ADDN NON-GRF/TALPA INFO:
        CRFI 16 -6C .33/.29/.43 OBS AT 2511251124.

        RMK: TWY ALPHA, 202511251111, DRY SNOW, 1/8IN. SLIPPERY CONDITIONS.
        """
    )
    #expect(
      report
        == .init(effects: [
          Self.surface(
            "16",
            [3, 2, 5],
            [50, 70, 40].enumerated().map {
              .init(
                type: .wetSnow,
                runwayThird: $0.offset + 1,
                coveragePercent: $0.element,
                depth: Self.inches(0.125)
              )
            }
          ),
          Self.surface(
            "34",
            [5, 2, 3],
            [
              .init(
                type: .wetSnow,
                runwayThird: nil,
                coveragePercent: 100,
                depth: Self.inches(0.125)
              )
            ]
          )
        ])
    )
  }

  @Test
  func `reads each third of an RSC separately, with DRY thirds empty`() throws {
    let report = try #require(
      Self.parse(
        notamText: "RSC 17L 6/6/6 10 PCT WET, DRY, DRY. VALID SEP 08 1450 - SEP 08 2250."
      )
    )
    let condition = try #require(report.effects.first?.surfaceCondition)
    #expect(condition.rwyCC == [6, 6, 6])
    #expect(
      condition.contaminants == [.init(type: .wet, runwayThird: 1, coveragePercent: 10, depth: nil)]
    )
  }

  @Test
  func `reads an obstacle report, tied to the runway its reference names`() {
    let report = Self.parse(
      notamText: """
        NYL OBST CRANE (ASN UNKNOWN) 323904N1143718W (1NM N APCH END RWY
        03L) UNKNOWN (60FT AGL) FLAGGED
        """
    )
    #expect(
      report
        == .init(effects: [
          .init(
            runway: "03L",
            obstacle: .init(
              heightAGL: Self.feet(60),
              heightMSL: nil,
              distance: .init(value: 1, unit: .nauticalMiles),
              distanceReference: "APCH END RWY 03L",
              direction: .N,
              runwayEnd: .init(runway: "03L", end: .approach)
            )
          )
        ])
    )
  }

  @Test
  func `reads an obstacle report whose reference names no runway`() {
    let report = Self.parse(
      notamText: """
        JFK OBST CRANE (ASN 2024-AEA-1604-NRA) 403906N0734931W (2.2NM WNW
        JFK) 114FT (100FT AGL) FLAGGED AND LGTD
        """
    )
    #expect(report?.effects.map(\.runway) == [nil])
    #expect(report?.effects.first?.obstacle?.heightMSL == Self.feet(114))
    #expect(report?.effects.first?.obstacle?.direction == .WNW)
    #expect(report?.effects.first?.obstacle?.runwayEnd == nil)
  }

  @Test(arguments: [
    ("0.4NM NW DEP END RWY 30", FormattedReport.RunwayEnd(runway: "30", end: .departure)),
    ("1.2NM SE APCH END RWY 9R", FormattedReport.RunwayEnd(runway: "09R", end: .approach)),
    ("0.2NM S RWY 12L", nil),
    ("0.5NM NE TWR APCH END RWY 12L", nil)
  ])
  func `names a runway end only when the reference is nothing else`(
    _ position: String,
    _ runwayEnd: FormattedReport.RunwayEnd?
  ) throws {
    let report = Self.parse(
      notamText:
        "ABC OBST TOWER (ASN 2026-AWP-1-OE) 374300N1221230W (\(position)) 185FT (170FT AGL)"
    )
    let obstacle = try #require(report?.effects.first?.obstacle)
    #expect(obstacle.runwayEnd == runwayEnd)
  }

  @Test
  func `reads a taxiway or apron FICON as no effects`() throws {
    let report = try #require(
      Self.parse(notamText: "FNT APRON ALL FICON PATCHY ICE OBS AT 2511280114.")
    )
    #expect(report.effects.isEmpty)
  }

  @Test(arguments: [
    // A cancellation.
    "ROA RWY 06 FICON 5/5/5 100 PCT WET OBS AT 2511260325.\nCANCELED",
    // A word outside the contaminant grammar.
    "RWY 16 FICON 5/5/5 SLIPPERY WHEN WET OBS AT 2511260325.",
    // A zero depth.
    "RWY 16 FICON 5/5/5 100 PCT 0IN WATER OBS AT 2511260325.",
    // Two lists for three thirds.
    "RWY 16 FICON 5/5/5 100 PCT WET, 100 PCT WET OBS AT 2511260325.",
    // A remark that closes the runway.
    "RSC 16/34 DRY. CLOSED BY N.O.T.A.M. VALID NOV 26 1253 - NOV 26 2053.",
    // A remark that reports a contaminant the list doesn't.
    "RSC 16/34 DRY. SOME SPORATIC SMALL ICE PATCHES. VALID NOV 26 1253 - NOV 26 2053.",
    // A non-GRF remark that states a closure.
    "RSC 16/34 DRY. VALID NOV 26 1253 - NOV 26 2053.\n\nRMK: RWY 16/34 CLSD 2200-0600.",
    // Two different reports for one runway.
    "RSC 07/25 DRY. RSC 07/25 100 PCT ICE. VALID AUG 31 1208 - SEP 01 1208.",
    // A SNOWTAM remark that states a closure.
    "SWBG0510 BGSS 09141722 (SNOWTAM 0510 BGSS 09141722 13 6/6/6 NR/NR/NR NR/NR/NR DRY/DRY/DRY REMARK/ RWY 13 CLSD.)",
    // A NOTAM in no report format.
    "RWY 09/27 CLSD"
  ])
  func `declines a NOTAM it can't read whole`(_ notamText: String) {
    #expect(Self.parse(notamText: notamText) == nil)
  }

  @Test
  func `states a report repeated word for word once`() throws {
    let report = try #require(
      Self.parse(
        notamText: "RSC 07/25 DRY. RSC 07/25 DRY. VALID AUG 31 1208 - SEP 01 1208."
      )
    )
    #expect(report.effects.map(\.runway) == ["07/25"])
  }
}
