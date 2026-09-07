import Defaults
import Foundation
import MeasurementKit
import SF50_Shared
import SwiftHtml

#if canImport(UIKit)
  import UIKit
#endif

// MARK: - Base Report Template

/// Base class for rendering TLR reports to HTML using the Template Method pattern.
///
/// ``BaseReportTemplate`` provides the rendering skeleton for generating HTML reports.
/// Subclasses override template methods to provide takeoff-specific or landing-specific
/// table layouts and formatting.
///
/// ## Template Methods
///
/// Subclasses must override:
/// - ``reportTitle()``: Returns the report title
/// - ``operationType()``: Returns "Takeoff" or "Landing"
/// - ``generateDataTable()``: Renders the conditions summary table
/// - ``generateRunwaysTable(_:)``: Renders the runway analysis table
/// - ``generatePerformanceTable(_:)``: Renders performance for a scenario
/// - ``extractPerformances(from:)``: Extracts runway performances from a scenario
/// - ``extractScenarioName(from:)``: Extracts the scenario name
/// - ``isValid(_:)``: Whether a runway's performance meets its requirements
/// - ``textTitle()``: The report's untranslated name, for the text report
/// - ``textUnitNames()``: The units the text report declares, if the operation adds any
/// - ``textPlannedData()``, ``runwayColumns()``, ``runwayCells(for:_:)``,
///   ``performanceColumns()``, ``performanceCells(for:)``: The operation-specific parts of the
///   fixed-width text report
///
/// ## Rendering
///
/// Call ``render(runways:scenarios:)`` to generate the complete HTML document:
///
/// ```swift
/// let template = TakeoffReportTemplate(input: input)
/// let html = template.render(runways: output.runwayInfo, scenarios: output.scenarios)
/// ```
///
/// ## See Also
///
/// - ``TakeoffReportTemplate``
/// - ``LandingReportTemplate``
class BaseReportTemplate<PerformanceType, ScenarioType> {
  // MARK: - Instance Properties

  let input: PerformanceInput
  let useAirportLocalTime: Bool

  let weightUnit: UnitMass
  let runwayLengthUnit: UnitLength
  let speedUnit: UnitSpeed
  let temperatureUnit: UnitTemperature
  let pressureUnit: UnitPressure

  // MARK: - Initialization

  init(input: PerformanceInput, useAirportLocalTime: Bool = false) {
    self.input = input
    self.useAirportLocalTime = useAirportLocalTime

    // Read unit preferences once during initialization
    self.weightUnit = Defaults[.weightUnit]
    self.runwayLengthUnit = Defaults[.runwayLengthUnit]
    self.speedUnit = Defaults[.speedUnit]
    self.temperatureUnit = Defaults[.temperatureUnit]
    self.pressureUnit = Defaults[.pressureUnit]
  }

  // MARK: - Instance Methods

  func reportDateFormat(for airport: AirportInput?) -> Date.FormatStyle {
    let displayTimeZone =
      if useAirportLocalTime {
        airport?.timeZone ?? .current
      } else {
        TimeZone(identifier: "UTC") ?? .current
      }
    return Date.FormatStyle(
      date: .omitted,
      time: .shortened,
      locale: Locale.current,
      calendar: Calendar.current,
      timeZone: displayTimeZone,
      capitalizationContext: .unknown
    )
    .month(.abbreviated)
    .day()
    .hour()
    .minute()
    .timeZone()
  }

  /// Names a shared report by operation, airport, runway, and the time it describes.
  ///
  /// Uses the same date format as the report body, so the file agrees with what is printed
  /// inside it rather than quoting a second, different time.
  func documentTitle() -> String {
    String(
      localized:
        "\(reportTitle()) \(input.airport.locationID) Rwy \(input.runway.name) \(input.date, format: reportDateFormat(for: input.airport))"
    )
  }

  // MARK: - Template Methods (to be overridden)

  // swiftlint:disable:next unavailable_function
  func reportTitle() -> String {
    fatalError("Subclasses must override reportTitle()")
  }

  // swiftlint:disable:next unavailable_function
  func generateDataTable() -> Table {
    fatalError("Subclasses must override generateDataTable()")
  }

  // swiftlint:disable:next unavailable_function
  func generateRunwaysTable(_: [RunwayInput: RunwayInfo]) -> Table {
    fatalError("Subclasses must override generateRunwaysTable(_:)")
  }

  // swiftlint:disable:next unavailable_function
  func generatePerformanceTable(_: [RunwayInput: PerformanceType]) -> Table {
    fatalError("Subclasses must override generatePerformanceTable(_:)")
  }

  // swiftlint:disable:next unavailable_function
  func extractPerformances(from _: ScenarioType) -> [RunwayInput: PerformanceType] {
    fatalError("Subclasses must override extractPerformances(from:)")
  }

  // swiftlint:disable:next unavailable_function
  func extractScenarioName(from _: ScenarioType) -> String {
    fatalError("Subclasses must override extractScenarioName(from:)")
  }

  // swiftlint:disable:next unavailable_function
  func textTitle() -> String {
    fatalError("Subclasses must override textTitle()")
  }

  /// The units the text report names in its header, one per kind of number it prints.
  ///
  /// Subclasses add any unit their own columns use, so nothing is printed without a unit
  /// declared somewhere.
  func textUnitNames() -> [String] {
    [
      "DIST \(textUnitSymbol(runwayLengthUnit))",
      "SPD \(textUnitSymbol(speedUnit))",
      "WT \(textUnitSymbol(weightUnit))"
    ]
  }

  // swiftlint:disable:next unavailable_function
  func textPlannedData() -> [String] {
    fatalError("Subclasses must override textPlannedData()")
  }

  // swiftlint:disable:next unavailable_function
  func runwayColumns() -> [TextColumn] {
    fatalError("Subclasses must override runwayColumns()")
  }

  // swiftlint:disable:next unavailable_function
  func runwayCells(for _: RunwayInput, _: RunwayInfo) -> [String] {
    fatalError("Subclasses must override runwayCells(for:_:)")
  }

  // swiftlint:disable:next unavailable_function
  func performanceColumns() -> [TextColumn] {
    fatalError("Subclasses must override performanceColumns()")
  }

  // swiftlint:disable:next unavailable_function
  func performanceCells(for _: PerformanceType) -> [String] {
    fatalError("Subclasses must override performanceCells(for:)")
  }

  // swiftlint:disable:next unavailable_function
  func isValid(_: PerformanceType) -> Bool {
    fatalError("Subclasses must override isValid(_:)")
  }

  // MARK: - Common Rendering

  func render(runways: [RunwayInput: RunwayInfo], scenarios: [ScenarioType]) -> String {
    let aircraft = input.aircraftInfo
    let forecastDate = input.date
    let generatedAt = Date.now
    let title = reportTitle()

    let doc = Document(.html) {
      Html {
        generateHead(title: title)
        Body {
          generateHeader(
            title: title,
            aircraft: aircraft,
            forecastDate: forecastDate,
            generatedAt: generatedAt
          )

          keptTogether {
            H2(String(localized: "\(operationType()) Data"))
            generateDataTable()
          }

          keptTogether {
            H3(String(localized: "Available Runways"))
            generateRunwaysTable(runways)
          }

          generateScenarioSections(scenarios: scenarios)
        }
      }
    }

    return DocumentRenderer(minify: false, indent: 2).render(doc)
  }

  // swiftlint:disable:next unavailable_function
  func operationType() -> String {
    fatalError("Subclasses must override operationType()")
  }

  // MARK: - Common HTML Components

  func generateHead(title: String) -> Head {
    Head {
      Title(title)
      Meta().charset("utf-8")
      Meta().name("viewport").content("width=device-width, initial-scale=1.0")
      Style(loadCSS(named: "normalize.css"))
      Style(loadCSS(named: "tlr.css"))
    }
  }

  @TagBuilder
  func generateHeader(
    title: String,
    aircraft: AircraftInfo,
    forecastDate: Date,
    generatedAt: Date
  ) -> Tag {
    let format = reportDateFormat(for: input.airport)
    H1(title)
    P(String(localized: "\(input.airport.locationID) • \(forecastDate, format: format)"))
      .class("h1-subtitle")
    P(
      String(
        localized:
          "\(aircraft.model) • BEW \(aircraft.emptyWeight.converted(to: weightUnit).formatted(.weight))"
      )
    )
    .class("h1-subtitle")
    P(formatWeatherSource())
      .class("h1-subtitle")
    P(String(localized: "Generated \(generatedAt, format: format)"))
      .class("h1-subtitle-small")
  }

  @TagBuilder
  func generateScenarioSections(scenarios: [ScenarioType]) -> Tag {
    for (index, scenario) in scenarios.enumerated() {
      let name = extractScenarioName(from: scenario)
      let performances = extractPerformances(from: scenario)
      let allInvalid = areAllPerformancesInvalid(performances)

      if index == 0 {
        // First scenario (Forecast Conditions) - always visible
        keptTogether {
          H3(String(localized: "\(operationType()) Performance • \(name)"))
            .class(allInvalid ? "scenario-invalid" : "")
          generatePerformanceTable(performances)
        }
      } else {
        // Other scenarios - accordion
        accordionSection(
          id: "\(operationType().lowercased())-scenario-\(index)",
          title: String(localized: "\(operationType()) Performance • \(name)"),
          isInvalid: allInvalid
        ) {
          generatePerformanceTable(performances)
        }
      }
    }
  }

  // MARK: - Formatting Helpers

  func formatWeatherSource() -> String {
    let conditions = input.conditions
    let source = conditions.source
    let validTime = conditions.validTime

    switch source {
      case .downloaded(let providers):
        // For downloaded weather, name the services it came from and the valid period
        let validPeriod = format(interval: validTime)
        return String(
          localized: "Weather: \(providers.localizedDescription) (\(validPeriod))"
        )

      case .ISA:
        return String(localized: "Weather: ISA")

      case .entered:
        return String(localized: "Weather: User")
    }
  }

  func format(interval: DateInterval) -> String {
    let start = interval.start
    let end = interval.end
    let duration = interval.duration
    let format = reportDateFormat(for: input.airport)

    // If duration is 1 hour or less, show as "Valid at [time]"
    if duration <= 3600 {
      return String(localized: "valid \(start, format: format)")
    }
    // Show as "Valid [start] to [end]"
    let startFormatted = start.formatted(format)
    let endFormatted = end.formatted(format)
    return String(localized: "valid \(startFormatted) to \(endFormatted)")
  }

  func format(windDirection direction: Measurement<UnitAngle>?, speed: Measurement<UnitSpeed>?)
    -> String
  {
    if let direction, let speed {
      return String(
        localized:
          "\(direction.asHeading, format: .heading)/\(speed.converted(to: speedUnit), format: .speed)"
      )
    }
    if let speed {
      return String(localized: "VRB/\(speed.converted(to: speedUnit), format: .speed)")
    }
    return String(localized: "calm")
  }

  func format(contamination: Contamination?) -> String {
    switch contamination {
      case .waterOrSlush(let depth):
        String(localized: "Water/Slush \(depth.converted(to: .inches), format: .depth)")
      case .slushOrWetSnow(let depth):
        String(localized: "Slush/Wet Snow \(depth.converted(to: .inches), format: .depth)")
      case .drySnow:
        String(localized: "Dry Snow")
      case .compactSnow:
        String(localized: "Compact Snow")
      case .wetRunway:
        String(localized: "Wet Runway")
      case .rwyCC(let rwyCC):
        String(localized: "RwyCC \(rwyCC, format: .number)")
      case nil:
        String(localized: "Dry")
    }
  }

  func format(performanceDistance value: Value<PerformanceDistance>?) -> [Tag] {
    return format(value: value) { perfDist in
      let marginClass = perfDist.margin.value >= 0 ? "margin-positive" : "margin-negative"

      return [
        Text(
          perfDist.distance.converted(to: runwayLengthUnit).formatted(
            .measurement(width: .narrow, usage: .asProvided, numberFormatStyle: .length)
          )
        ),
        Span(
          String(
            localized:
              " (\(perfDist.margin.converted(to: runwayLengthUnit), format: .length(plusSign: true)))"
          )
        ).class(marginClass)
      ]
    }
  }

  /// How a value that carries no number reads, and the class that colours it.
  ///
  /// Shared so the HTML tables and the text summary cannot drift apart on what "offscale"
  /// prints as. Returns `nil` when the value does carry a number.
  func unavailableDescription<T>(of value: Value<T>) -> (text: String, cssClass: String)? {
    switch value {
      case .value, .valueWithUncertainty: nil
      case .invalid: (String(localized: "Inv"), "invalid")
      case .notAvailable: (String(localized: "-"), "not-available")
      case .notAuthorized: (String(localized: "N/A"), "invalid")
      case .offscaleHigh, .offscaleLow: (String(localized: "N/A"), "not-available")
    }
  }

  func format<T>(value: Value<T>, formatter: (T) -> [Tag]) -> [Tag] {
    guard let unavailable = unavailableDescription(of: value) else {
      return value.nominal.map(formatter) ?? []
    }
    return [Span(unavailable.text).class(unavailable.cssClass)]
  }

  func format<T>(value: Value<T>?, formatter: (T) -> [Tag]) -> [Tag] {
    guard let value else {
      return [Span(String(localized: "-")).class("not-available")]
    }

    return format(value: value, formatter: formatter)
  }

  func format(speed value: Value<Measurement<UnitSpeed>>?) -> [Tag] {
    format(value: value) { [Text($0.converted(to: speedUnit).formatted(.speed))] }
  }

  func format(slope value: Value<Measurement<UnitSlope>>?) -> [Tag] {
    format(value: value) { [Text($0.asGradient.formatted(.gradient))] }
  }

  func format(bool value: Value<Bool>?) -> [Tag] {
    format(value: value) { bool in
      [Text(String(localized: "\(bool ? "✓" : "✗")"))]
    }
  }

  // MARK: - Utility Methods

  func loadCSS(named name: String) -> String {
    #if canImport(UIKit)
      if let asset = NSDataAsset(name: name),
        let cssString = String(data: asset.data, encoding: .utf8)
      {
        return cssString
      }
    #endif
    return ""
  }

  /// Groups a heading with the table it introduces so that printing cannot separate them.
  ///
  /// The print stylesheet keeps this block off a page boundary. `break-after: avoid` on the
  /// heading would say the same thing more directly, but the print formatter ignores it and
  /// honors `page-break-inside`, so the pair has to be a block for the rule to have something
  /// to hold together.
  func keptTogether(@TagBuilder content: () -> Tag) -> Tag {
    Div(content()).class("kept-together")
  }

  func accordionSection(id: String, title: String, isInvalid: Bool = false, content: () -> Tag)
    -> Tag
  {
    Div {
      Input()
        .type(.checkbox)
        .id(id)
        .class("accordion-toggle")
      Label {
        H3(title)
          .class(isInvalid ? "scenario-invalid" : "")
      }
      .for(id)
      .class("accordion-header")
      Div(content())
        .class("accordion-content")
    }
    .class("accordion-item")
  }

  // MARK: - Performance Validation

  func areAllPerformancesInvalid(_ performances: [RunwayInput: PerformanceType]) -> Bool {
    guard !performances.isEmpty else { return true }
    return performances.values.allSatisfy { !isValid($0) }
  }
}

extension AircraftInfo {
  var model: String {
    switch aircraftType {
      case .g1: String(localized: "SF50 G1")
      case .g2: String(localized: "SF50 G2")
      case .g2Plus: String(localized: "SF50 G2+")
    }
  }
}
