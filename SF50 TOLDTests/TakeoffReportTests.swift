import Foundation
import PDFKit
import SF50_Shared
import Testing

@testable import SF50_TOLD

/// Exercises TLR report generation end to end, through to the PDF a pilot files.
///
/// Serialized because generating two reports at once deadlocks.
@Suite(.serialized)
struct `Takeoff Report` {

  private static let scenarioBehindAccordion = "Hot Day"

  /// A sea-level airport flown at mid weight on a standard day, with a 5,000 ft paved runway
  /// for each name given.
  private static func performanceInput(runwayNames: [String] = ["36"]) -> PerformanceInput {
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
        length: .init(value: 5000, unit: .feet),
        takeoffRun: nil,
        takeoffDistance: nil,
        landingDistance: nil,
        surfaceType: .paved,
        airport: airport
      )
    }
    airport.runways = runways

    return PerformanceInput(
      airport: .init(from: airport),
      runway: .init(from: runways[0], airport: airport),
      conditions: .init(
        windDirection: .init(value: 360, unit: .degrees),
        windSpeed: .init(value: 10, unit: .knots),
        temperature: .init(value: 15, unit: .celsius),
        seaLevelPressure: .init(value: 29.92, unit: .inchesOfMercury)
      ),
      weight: .init(value: 5500, unit: .pounds),
      flapSetting: .flaps50,
      safetyFactor: 1.0,
      useRegressionModel: false,
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
