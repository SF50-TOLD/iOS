import Foundation
import PDFKit
import SF50_Shared
import Testing

@testable import SF50_TOLD

/// Exercises TLR report generation end to end, through to the PDF a pilot files.
@Suite
struct `Takeoff Report` {

  private static let scenarioBehindAccordion = "Hot Day"
  private static let pavementLength = Measurement(value: 5000, unit: UnitLength.feet)

  /// A sea-level airport flown at mid weight on a standard day, with a paved runway of
  /// ``pavementLength`` for each name given, declaring the takeoff distance given.
  private static func performanceInput(
    runwayNames: [String] = ["36"],
    takeoffRun: Measurement<UnitLength>? = nil,
    takeoffDistance: Measurement<UnitLength>? = nil,
    obstacle: (height: Measurement<UnitLength>, distance: Measurement<UnitLength>)? = nil,
    useRegressionModel: Bool = false
  ) -> PerformanceInput {
    let airport = Airport(
      recordID: "TEST",
      locationID: "TEST",
      ICAO_ID: "KTST",
      name: "Test Airport",
      city: "Test City",
      dataSource: .NASR,
      latitude: .init(value: 37, unit: .degrees),
      longitude: .init(value: -122, unit: .degrees),
      elevation: .init(value: 0, unit: .feet),
      variation: .init(value: 0, unit: .degrees),
      timeZone: .init(identifier: "America/Los_Angeles")
    )
    let runways = runwayNames.map { name in
      Runway(
        name: name,
        elevation: nil,
        trueHeading: .init(value: 360, unit: .degrees),
        gradient: 0,
        length: pavementLength,
        takeoffRun: takeoffRun,
        takeoffDistance: takeoffDistance,
        landingDistance: nil,
        surfaceType: .paved,
        airport: airport
      )
    }
    airport.runways = runways

    let notam = obstacle.map {
      NOTAM(runway: runways[0], obstacleHeight: $0.height, obstacleDistance: $0.distance)
    }

    return PerformanceInput(
      airport: .init(from: airport, notams: notam.map { [runways[0].name: $0] } ?? [:]),
      runway: .init(from: runways[0], airport: airport, notam: notam),
      conditions: .init(
        windDirection: .init(value: 360, unit: .degrees),
        windSpeed: .init(value: 10, unit: .knots),
        temperature: .init(value: 15, unit: .celsius),
        seaLevelPressure: .init(value: 29.92, unit: .inchesOfMercury)
      ),
      weight: .init(value: 5500, unit: .pounds),
      flapSetting: .flaps50,
      safetyFactor: 1.0,
      useRegressionModel: useRegressionModel,
      aircraftType: .g1,
      emptyWeight: .init(value: 3550, unit: .pounds),
      date: .now
    )
  }

  /// Four runways and a second scenario, so the report is long enough to paginate and has a
  /// scenario that only the print stylesheet reveals.
  private static func multiRunwayReport() throws -> Report {
    try generateTakeoffReport(
      input: performanceInput(runwayNames: ["36", "18", "09", "27"]),
      scenarios: [
        PerformanceScenario(name: "Forecast Conditions"),
        PerformanceScenario(
          deltaTemperature: .init(value: 20, unit: .celsius),
          name: scenarioBehindAccordion
        )
      ]
    )
  }

  private static func analysis(of input: PerformanceInput) throws
    -> ReportOutput<TakeoffPerformanceScenario>
  {
    try TakeoffReportData(
      input: input,
      scenarios: [PerformanceScenario(name: "Forecast Conditions")]
    ).generate()
  }

  /// The takeoff-distance margin the planned runway carries under the only scenario.
  private static func takeoffMargin(of input: PerformanceInput) throws
    -> Measurement<UnitLength>
  {
    let scenario = try #require(analysis(of: input).scenarios.first),
      performance = try #require(scenario.runways[input.runway]),
      totalDistance = try #require(performance.totalDistance?.nominal)
    return totalDistance.margin
  }

  /// What holds the planned runway's maximum takeoff weight down.
  private static func limitingFactor(of input: PerformanceInput) throws -> LimitingFactor {
    try #require(analysis(of: input).runwayInfo[input.runway]).limitingFactor
  }

  private static func text(of document: PDFDocument) -> String {
    (0..<document.pageCount)
      .compactMap { document.page(at: $0)?.string }
      .joined(separator: "\n")
  }

  @Test
  func `renders a takeoff report naming its airport and scenario`() throws {
    let input = Self.performanceInput()
    let report = try generateTakeoffReport(
      input: input,
      scenarios: [PerformanceScenario(name: "Forecast Conditions")]
    )

    let isHTML = report.html.contains("<html"),
      namesAirport = report.html.contains(input.airport.locationID),
      namesScenario = report.html.contains("Forecast Conditions")

    // The rendered HTML goes with a failure only, so a green run carries no attachment.
    if !(isHTML && namesAirport && namesScenario) {
      Attachment.record(report.html, named: "takeoff-report.html")
    }

    #expect(isHTML, "Report should be an HTML document")
    #expect(namesAirport, "Report should name the airport")
    #expect(namesScenario, "Report should name the scenario")
  }

  /// The text report is the whole report, not a digest, and it has to survive a teleprinter:
  /// upper case, 7-bit ASCII, and a row for every runway under every scenario.
  @Test
  func `reports every runway and scenario as fixed-width text`() throws {
    let text = try Self.multiRunwayReport().textReport,
      lines = text.split(separator: "\n", omittingEmptySubsequences: false),
      isASCII = text.allSatisfy(\.isASCII),
      isUpperCased = text == text.uppercased(),
      fitsTeleprinter = lines.allSatisfy { $0.count <= 72 },
      // One performance table per scenario, each headed by the same column row.
      performanceTables = text.components(separatedBy: "TODR").count - 1

    if !(isASCII && isUpperCased && fitsTeleprinter) {
      Attachment.record(text, named: "takeoff-report.txt")
    }

    #expect(isASCII, "A teleprinter carries only 7-bit ASCII")
    #expect(
      !text.contains(","),
      "Numbers should carry no grouping separator, and no label should need a comma"
    )
    #expect(isUpperCased, "The report should be upper case throughout")
    #expect(fitsTeleprinter, "Lines should stay within a teleprinter width")
    #expect(text.contains("TEST/36"), "The header should name the airport and planned runway")
    #expect(
      text.hasPrefix("TAKEOFF REPORT ") && text.contains("SF50 G1"),
      "The header should name the operation and the aircraft in fixed English"
    )
    #expect(performanceTables == 2, "Each scenario should get its own performance table")
    #expect(
      text.contains(Self.scenarioBehindAccordion.uppercased()),
      "The report should name every scenario"
    )
  }

  /// A clearway, a stopway, or a displaced threshold makes the declared distance shorter than the
  /// pavement it sits on, and the margin has to be measured against what is declared — measuring
  /// against the pavement overstates it, on the optimistic side.
  @Test
  func `measures margin against the declared distance, not the pavement`() throws {
    let shortfall = Measurement(value: 1200, unit: UnitLength.feet),
      overPavement = try Self.takeoffMargin(of: Self.performanceInput()),
      overDeclared = try Self.takeoffMargin(
        of: Self.performanceInput(takeoffDistance: Self.pavementLength - shortfall)
      ),
      lost = (overPavement - overDeclared).converted(to: .feet)

    #expect(
      abs(lost.value - shortfall.value) < 1,
      "The declared distance should cost the margin every foot it gives up to the pavement"
    )
  }

  /// A clearway lets the distance to 50 feet run past the end of the pavement, but the ground run
  /// cannot: a weight that lifts off beyond the takeoff run available is field-limited however
  /// much clearway follows it.
  @Test
  func `limits weight by the takeoff run, not only the distance to 50 feet`() throws {
    let
      overClearway = try Self.limitingFactor(
        of: Self.performanceInput(takeoffRun: .init(value: 1000, unit: .feet))
      ),
      overPavement = try Self.limitingFactor(of: Self.performanceInput())

    #expect(overClearway == .field, "A takeoff run too short for the ground run is a field limit")
    #expect(overPavement != .field, "The same runway without a clearway is not field-limited")
  }

  /// The maximum-weight search has to reach the same verdict whichever model computed the figures.
  /// The regression model reports every figure with an uncertainty band, and a search that reads
  /// only bare values sees nothing to test the obstacle against — so it publishes a weight that
  /// was never checked against it.
  @Test(arguments: [false, true])
  func `limits weight by an obstacle under either performance model`(
    useRegressionModel: Bool
  ) throws {
    let obstacle = (
      height: Measurement(value: 200, unit: UnitLength.feet),
      distance: Measurement(value: 3000, unit: UnitLength.feet)
    )

    let limitedByObstacle = try Self.limitingFactor(
      of: Self.performanceInput(obstacle: obstacle, useRegressionModel: useRegressionModel)
    )
    let unobstructed = try Self.limitingFactor(
      of: Self.performanceInput(useRegressionModel: useRegressionModel)
    )

    #expect(
      limitedByObstacle == .obstacle,
      "An obstacle the climb cannot clear should limit the weight"
    )
    #expect(
      unobstructed != .obstacle,
      "The same runway without the obstacle is not obstacle-limited"
    )
  }

  /// A shared file should identify the operation it describes rather than be one of many
  /// identically named ones.
  @MainActor
  @Test
  func `names the PDF after its airport, runway, and time`() throws {
    let report = try Self.multiRunwayReport(),
      data = try ReportPDF.render(html: report.html, documentTitle: report.documentTitle),
      document = try #require(PDFDocument(data: data)),
      recordedTitle = document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String

    #expect(report.documentTitle.contains("TEST"), "The name should carry the airport")
    #expect(report.documentTitle.contains("36"), "The name should carry the runway")
    #expect(recordedTitle == report.documentTitle, "The PDF should record that name")
    #expect(!report.fileName.contains("/"), "A file name cannot carry a path separator")
  }

  /// Covers the two things that fail silently in the PDF: page geometry, without which the
  /// renderer paginates nothing, and the print stylesheet, without which every scenario past the
  /// first prints as an empty panel. An accordion's heading renders either way, so proving the
  /// panel opened means counting the performance tables rather than looking for the heading.
  @MainActor
  @Test
  func `prints a paginated PDF including the scenarios collapsed on screen`() throws {
    let
      data = try ReportPDF.render(
        html: Self.multiRunwayReport().html,
        documentTitle: "Test Report"
      ),
      document = try #require(PDFDocument(data: data), "PDF data should parse as a document"),
      text = Self.text(of: document),
      performanceTables = text.components(separatedBy: "Ground Run").count - 1

    if document.pageCount <= 1 || performanceTables != 2 {
      Attachment.record(data, named: "takeoff-report.pdf")
    }

    #expect(document.pageCount > 1, "A four-runway, two-scenario report should exceed one page")
    #expect(
      text.contains(Self.scenarioBehindAccordion),
      "The report should name the accordion scenario"
    )
    #expect(
      performanceTables == 2,
      "Both scenarios' performance tables should print, not just the uncollapsed one"
    )
  }
}
