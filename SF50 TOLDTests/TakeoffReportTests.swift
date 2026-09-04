import Foundation
import SF50_Shared
import Testing

@testable import SF50_TOLD

/// Exercises TLR report generation end to end.
@Suite
struct `Takeoff Report` {

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

  @Test
  func `renders a takeoff report naming its airport and scenario`() throws {
    let input = Self.performanceInput()
    let report = try generateTakeoffReport(
      input: input,
      scenarios: [PerformanceScenario(name: "Forecast Conditions")]
    )

    let isHTML = report.contains("<html"),
      namesAirport = report.contains(input.airport.locationID),
      namesScenario = report.contains("Forecast Conditions")

    // The rendered HTML goes with a failure only, so a green run carries no attachment.
    if !(isHTML && namesAirport && namesScenario) {
      Attachment.record(report, named: "takeoff-report.html")
    }

    #expect(isHTML, "Report should be an HTML document")
    #expect(namesAirport, "Report should name the airport")
    #expect(namesScenario, "Report should name the scenario")
  }
}
