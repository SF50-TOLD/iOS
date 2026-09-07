import Foundation
import MeasurementKit
import SF50_Shared
import SwiftHtml

#if canImport(UIKit)
  import UIKit
#endif

// MARK: - Takeoff Report Template

/// Renders takeoff performance data to HTML format.
///
/// ``TakeoffReportTemplate`` extends ``BaseReportTemplate`` with takeoff-specific
/// table layouts showing:
/// - Takeoff data (airport, runway, OAT, wind, QNH, TOW)
/// - Runway analysis (length, MTOW, limiting factor)
/// - Performance tables (ground run, total distance, climb rate)
class TakeoffReportTemplate: BaseReportTemplate<
  TakeoffRunwayPerformance, TakeoffPerformanceScenario
>
{

  // MARK: - Template Method Implementations

  override func reportTitle() -> String {
    String(localized: "Takeoff Report")
  }

  override func operationType() -> String {
    String(localized: "Takeoff")
  }

  override func extractPerformances(from scenario: TakeoffPerformanceScenario) -> [RunwayInput:
    TakeoffRunwayPerformance]
  {
    scenario.runways
  }

  override func extractScenarioName(from scenario: TakeoffPerformanceScenario) -> String {
    scenario.scenarioName
  }

  override func isValid(_ performance: TakeoffRunwayPerformance) -> Bool {
    performance.isValid
  }

  /// Climb gradient is always feet per nautical mile, whatever distance unit is preferred, so
  /// the header has to say so rather than let the reader assume the distance unit above.
  override func textTitle() -> String {
    "TAKEOFF REPORT"
  }

  override func textUnitNames() -> [String] {
    super.textUnitNames()
      + ["CLB \(textUnitSymbol(UnitSlope.feetPerNauticalMile))"]
  }

  override func textPlannedData() -> [String] {
    [
      "PTOW \(whole(input.weight.converted(to: weightUnit).value))"
        + " BEW \(whole(input.emptyWeight.converted(to: weightUnit).value))"
        + " FLAPS \(textFlapSetting(input.flapSetting))"
        + " SF \(decimal(input.safetyFactor, places: 2))"
    ]
  }

  override func runwayColumns() -> [TextColumn] {
    [
      .init(heading: "RWY", width: 4, alignment: .leading),
      .init(heading: "LENGTH", width: 7),
      .init(heading: "MTOW", width: 7),
      .init(heading: "LIM", width: 5, alignment: .leading)
    ]
  }

  override func runwayCells(for runway: RunwayInput, _ info: RunwayInfo) -> [String] {
    [
      whole(runway.length.converted(to: runwayLengthUnit).value),
      whole(info.maxWeight.converted(to: weightUnit).value),
      textLimitingFactor(info.limitingFactor)
    ]
  }

  override func performanceColumns() -> [TextColumn] {
    [
      .init(heading: "RWY", width: 4, alignment: .leading),
      .init(heading: "TOR", width: 7),
      .init(heading: "MARGIN", width: 8),
      .init(heading: "TODR", width: 8),
      .init(heading: "MARGIN", width: 8),
      .init(heading: "CLB", width: 7)
    ]
  }

  override func performanceCells(for performance: TakeoffRunwayPerformance) -> [String] {
    let groundRun = textDistance(performance.groundRun),
      total = textDistance(performance.totalDistance)
    return [
      groundRun.distance, groundRun.margin,
      total.distance, total.margin,
      textValue(performance.climbRate) { whole($0.asGradient.value) }
    ]
  }

  override func generateDataTable() -> Table {
    Table {
      Thead {
        Tr {
          Th(String(localized: "A/P"))
          Th(String(localized: "Rwy"))
          Th(String(localized: "OAT"))
          Th(String(localized: "Wind"))
          Th(String(localized: "QNH"))
          Th(String(localized: "TOW"))
        }
      }
      Tbody {
        Tr {
          Td(input.airport.locationID)
          Td(input.runway.name)
          Td(
            (input.conditions.temperature ?? standardTemperature).converted(to: temperatureUnit)
              .formatted(
                .temperature
              )
          )
          Td(
            format(windDirection: input.conditions.windDirection, speed: input.conditions.windSpeed)
          )
          Td(
            (input.conditions.seaLevelPressure ?? standardSeaLevelPressure)
              .converted(to: pressureUnit)
              .formatted(.airPressure(in: pressureUnit))
          )
          Td(input.weight.converted(to: weightUnit).formatted(.weight))
        }
      }
    }
  }

  override func generateRunwaysTable(_ runways: [RunwayInput: RunwayInfo]) -> Table {
    Table {
      Thead {
        Tr {
          Th(String(localized: "Rwy"))
          Th(String(localized: "Length"))
          Th(String(localized: "MTOW"))
          Th(String(localized: "Limit"))
        }
      }
      Tbody {
        for (runwayInput, info) in runways.sorted(by: { $0.key < $1.key }) {
          Tr {
            Th(runwayInput.name)
            Td(runwayInput.length.converted(to: runwayLengthUnit).formatted(.length))
            Td(info.maxWeight.converted(to: weightUnit).formatted(.weight))
            Td(info.limitingFactor.rawValue)
          }
        }
      }
    }
  }

  override func generatePerformanceTable(_ performances: [RunwayInput: TakeoffRunwayPerformance])
    -> Table
  {
    Table {
      Thead {
        Tr {
          Th(String(localized: "Runway"))
          Th(String(localized: "Ground Run (margin)"))
          Th(String(localized: "Total Dist (margin)"))
          Th(String(localized: "Climb Rate"))
        }
      }
      Tbody {
        for (runwayInput, perf) in performances.sorted(by: { $0.key < $1.key }) {
          let rowClass = perf.isValid ? "" : "invalid"
          Tr {
            Th(runwayInput.name)

            // Ground Run
            Td {
              format(performanceDistance: perf.groundRun)
            }

            // Total Distance
            Td {
              format(performanceDistance: perf.totalDistance)
            }

            // Climb Rate
            Td(format(slope: perf.climbRate))
          }
          .class(rowClass)
        }
      }
    }
  }
}
