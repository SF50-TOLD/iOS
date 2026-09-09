import Foundation
import SF50_Shared
import SwiftHtml

#if canImport(UIKit)
  import UIKit
#endif

// MARK: - Landing Report Template

/// Renders landing performance data to HTML format.
///
/// ``LandingReportTemplate`` extends ``BaseReportTemplate`` with landing-specific
/// table layouts showing:
/// - Landing data (airport, runway, OAT, wind, QNH, LW, config)
/// - Runway analysis (ALD, MLW, limiting factor, condition)
/// - Performance tables (Vref, landing run, landing distance, go-around compliance)
class LandingReportTemplate: BaseReportTemplate<
  LandingRunwayPerformance, LandingPerformanceScenario
>
{

  // MARK: - Template Method Implementations

  override func reportTitle() -> String {
    String(localized: "Landing Report")
  }

  override func operationType() -> String {
    String(localized: "Landing")
  }

  override func extractPerformances(from scenario: LandingPerformanceScenario) -> [RunwayInput:
    LandingRunwayPerformance]
  {
    scenario.runways
  }

  override func extractScenarioName(from scenario: LandingPerformanceScenario) -> String {
    scenario.scenarioName
  }

  override func isValid(_ performance: LandingRunwayPerformance) -> Bool {
    performance.isValid
  }

  override func textTitle() -> String {
    "LANDING REPORT"
  }

  override func textPlannedData() -> [String] {
    [
      "PLW \(whole(input.weight.converted(to: weightUnit).value))"
        + " BEW \(whole(input.emptyWeight.converted(to: weightUnit).value))"
        + " FLAPS \(textFlapSetting(input.flapSetting))"
        + " SF \(decimal(input.safetyFactor, places: 2))",
      "VREF ADD "
        + whole(
          Measurement(value: input.VREFAdditiveKts, unit: UnitSpeed.knots)
            .converted(to: speedUnit).value
        )
    ]
  }

  override func runwayColumns() -> [TextColumn] {
    [
      .init(heading: "RWY", width: 4, alignment: .leading),
      .init(heading: "LDA", width: 7),
      .init(heading: "MLW", width: 7),
      .init(heading: "LIM", width: 5, alignment: .leading),
      .init(heading: "COND", width: 20, alignment: .leading)
    ]
  }

  override func runwayCells(for runway: RunwayInput, _ info: RunwayInfo) -> [String] {
    [
      whole(runway.availableLandingDistance.converted(to: runwayLengthUnit).value),
      whole(info.maxWeight.converted(to: weightUnit).value),
      textLimitingFactor(info.limitingFactor),
      textContamination(info.contamination)
    ]
  }

  override func performanceColumns() -> [TextColumn] {
    [
      .init(heading: "RWY", width: 4, alignment: .leading),
      .init(heading: "VREF", width: 6),
      .init(heading: "ROLL", width: 8),
      .init(heading: "MARGIN", width: 8),
      .init(heading: "LDR", width: 8),
      .init(heading: "MARGIN", width: 8),
      .init(heading: "APPR CLB", width: 9, alignment: .leading)
    ]
  }

  override func performanceCells(for performance: LandingRunwayPerformance) -> [String] {
    let run = textDistance(performance.landingRun),
      total = textDistance(performance.landingDistance)
    return [
      textSpeed(performance.Vref),
      run.distance, run.margin,
      total.distance, total.margin,
      textBool(performance.meetsGoAroundRequirement)
    ]
  }

  override func generateDataTable() -> Table {
    Table {
      Thead {
        Tr {
          Th(
            String(
              localized: "A/P",
              comment:
                "Column header over the airport identifier. “A/P” abbreviates “airport”, not “autopilot”."
            )
          )
          Th(String(localized: "Rwy"))
          Th(String(localized: "OAT"))
          Th(String(localized: "Wind"))
          Th(String(localized: "QNH"))
          Th(String(localized: "LW"))
          Th(String(localized: "Config"))
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
          Td(SF50_TOLD.format(flapSetting: input.flapSetting, short: true))
        }
      }
    }
  }

  override func generateRunwaysTable(_ runways: [RunwayInput: RunwayInfo]) -> Table {
    Table {
      Thead {
        Tr {
          Th(String(localized: "Rwy"))
          Th(
            String(
              localized: "LDA",
              comment:
                "Column header over the landing distance available. “LDA” is the ICAO abbreviation and is left as it is in every language."
            )
          )
          Th(String(localized: "MLW"))
          Th(String(localized: "Limit"))
          Th(String(localized: "Cond"))
        }
      }
      Tbody {
        for (runwayInput, info) in runways.sorted(by: { $0.key < $1.key }) {
          Tr {
            Th(runwayInput.name)
            Td(
              runwayInput.availableLandingDistance.converted(to: runwayLengthUnit)
                .formatted(.length)
            )
            Td(info.maxWeight.converted(to: weightUnit).formatted(.weight))
            Td(info.limitingFactor.rawValue)
            Td(format(contamination: info.contamination))
          }
        }
      }
    }
  }

  override func generatePerformanceTable(_ performances: [RunwayInput: LandingRunwayPerformance])
    -> Table
  {
    Table {
      Thead {
        Tr {
          Th(String(localized: "Rwy"))
          Th(String(localized: "VREF"))
          Th(String(localized: "Ldg Run (margin)"))
          Th(String(localized: "Ldg Dist (margin)"))
          Th(String(localized: "Meets G/A Req?"))
        }
      }
      Tbody {
        for (runwayInput, perf) in performances.sorted(by: { $0.key < $1.key }) {
          let rowClass = perf.isValid ? "" : "invalid"
          Tr {
            Th(runwayInput.name)
            Td(format(speed: perf.Vref))
            Td(format(performanceDistance: perf.landingRun))
            Td(format(performanceDistance: perf.landingDistance))
            Td(format(bool: perf.meetsGoAroundRequirement))
          }
          .class(rowClass)
        }
      }
    }
  }
}
