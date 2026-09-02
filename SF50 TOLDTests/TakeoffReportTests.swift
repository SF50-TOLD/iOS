import Foundation
import SF50_Shared
import Testing

@testable import SF50_TOLD

/// Exercises TLR report generation end to end.
@Suite("Takeoff Report")
struct TakeoffReportTests {

  /// A sea-level airport with one 5,000 ft paved runway, flown at mid weight on a standard day.
  private static func performanceInput() -> PerformanceInput {
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
    let runway = Runway(
      name: "36",
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
    airport.runways = [runway]

    return PerformanceInput(
      airport: .init(from: airport),
      runway: .init(from: runway, airport: airport),
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

  @Test("Renders a takeoff report and attaches it")
  func rendersTakeoffReport() throws {
    let input = Self.performanceInput()
    let report = try generateTakeoffReport(
      input: input,
      scenarios: [PerformanceScenario(name: "Forecast Conditions")]
    )

    Attachment.record(report, named: "takeoff-report.html")

    #expect(report.contains("<html"))
    #expect(report.contains(input.airport.locationID))
    #expect(report.contains("Forecast Conditions"))
  }
}
