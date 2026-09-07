import Foundation
import SF50_Shared

/// A fixed-width column in the text report.
struct TextColumn {
  let heading: String
  let width: Int
  let alignment: Alignment

  init(heading: String, width: Int, alignment: Alignment = .trailing) {
    self.heading = heading
    self.width = width
    self.alignment = alignment
  }

  /// Which edge of the column a value sits against.
  ///
  /// Numbers range right so that digits of the same magnitude line up; names and codes range
  /// left so they sit under their heading rather than drifting away from it.
  enum Alignment { case leading, trailing }
}

extension String {
  fileprivate func trimmingTrailingSpaces() -> String {
    String(reversed().drop { $0 == " " }.reversed())
  }
}

extension BaseReportTemplate {
  /// Punctuation that would otherwise be dropped on the way to 7-bit ASCII, and what it becomes.
  fileprivate static var asciiEquivalents: KeyValuePairs<String, String> {
    [
      "\u{2212}": "-", "\u{2013}": "-", "\u{2014}": "-",
      "\u{2018}": "'", "\u{2019}": "'",
      "\u{201C}": "\"", "\u{201D}": "\"",
      "\u{2032}": "", "\u{00B0}": ""
    ]
  }
}

/// Renders the report as fixed-width text, in the shape of an ACARS performance uplink.
///
/// The document a pilot files is the PDF; this is the same report in the form that can be typed
/// into a scratchpad or read over a radio. It follows the teleprinter conventions that shape an
/// ACARS message — upper case, 7-bit ASCII, columns aligned by padding, units declared once
/// rather than repeated in every cell, and times always in Zulu.
///
/// Nothing here is localized. A performance report is read by whoever receives it, which may not
/// be whoever sent it, so its wording and its numbers have to be the same everywhere: fixed
/// English labels, a full stop for a decimal point, and no grouping separators. Every number is
/// therefore built with `String(format:)` rather than a locale-aware `FormatStyle`.
extension BaseReportTemplate {

  /// The width every banner is laid out to: whatever the widest table needs, so that a banner
  /// never stops short of the columns beneath it.
  private var reportWidth: Int {
    let flag = 1,
      widest = performanceColumns().reduce(flag) { $0 + $1.width }
    return max(48, widest)
  }

  func textReport(runways: [RunwayInput: RunwayInfo], scenarios: [ScenarioType]) -> String {
    var lines = textHeader()

    lines.append("")
    lines.append(banner("RUNWAYS"))
    lines += table(
      columns: runwayColumns(),
      rows: runways.sorted { $0.key < $1.key }.map { runway, info in
        (flagged: false, cells: [runway.name] + runwayCells(for: runway, info))
      }
    )

    for scenario in scenarios {
      let performances = extractPerformances(from: scenario)
      lines.append("")
      lines.append(banner("PERF \(extractScenarioName(from: scenario))"))
      lines += table(
        columns: performanceColumns(),
        rows: performances.sorted { $0.key < $1.key }.map { runway, performance in
          (
            flagged: !isValid(performance),
            cells: [runway.name] + performanceCells(for: performance)
          )
        }
      )
    }

    lines.append("")
    lines.append("* = DOES NOT MEET REQUIREMENTS")

    // A trailing-aligned last column pads to its width; nothing should carry that padding out.
    return lines.map { $0.trimmingTrailingSpaces() }.joined(separator: "\n")
  }

  // MARK: - Sections

  private func textHeader() -> [String] {
    ([
      "\(textTitle()) \(input.airport.locationID)/\(input.runway.name)",
      "\(zulu(input.date)) \(textModel())"
    ] + textPlannedData() + [conditionsLine(), weatherLine(), unitsLine()]).map(teletype)
  }

  /// The planned conditions, prefixed P as a TLR does, so that a value read off this report is
  /// never mistaken for one observed at the hold-short line.
  ///
  /// Grouping separators are suppressed: a teleprinter report is read in fixed columns, and a
  /// comma inside a number is one more thing to misread.
  private func conditionsLine() -> String {
    let
      temperature = (input.conditions.temperature ?? standardTemperature)
        .converted(to: temperatureUnit),
      pressure = (input.conditions.seaLevelPressure ?? standardSeaLevelPressure)
        .converted(to: pressureUnit)
    return "POAT \(whole(temperature.value))\(textUnitSymbol(temperatureUnit))"
      + " PQNH \(decimal(pressure.value, places: 2))\(textUnitSymbol(pressureUnit))"
      + " WIND \(wind())"
  }

  private func wind() -> String {
    guard let speed = input.conditions.windSpeed, speed.value > 0 else {
      return "CALM"
    }
    guard let direction = input.conditions.windDirection else {
      return "VRB/\(whole(speed.converted(to: speedUnit).value))"
    }
    let heading = String(format: "%03d", Int(direction.asHeading.value.rounded()))
    return "\(heading)/\(whole(speed.converted(to: speedUnit).value))"
  }

  private func weatherLine() -> String {
    switch input.conditions.source {
      case .downloaded(let providers):
        "WX \(providers.names.joined(separator: "/")) "
          + "VALID \(zulu(input.conditions.validTime.start))"
      case .ISA: "WX ISA"
      case .entered: "WX ENTERED"
    }
  }

  /// Distances, speeds and weights are declared once here rather than repeated in every cell,
  /// as an uplink does. Temperature and pressure carry theirs inline, where they appear once.
  private func unitsLine() -> String {
    textUnitNames().joined(separator: " / ")
  }

  /// A unit's symbol as a teleprinter can carry it: `°C` becomes `C`, `inHg` becomes `INHG`.
  /// Taken from the unit itself so that it cannot disagree with the numbers beside it.
  func textUnitSymbol(_ unit: Unit) -> String {
    teletype(unit.symbol).replacingOccurrences(of: " ", with: "")
  }

  // MARK: - Layout

  private func banner(_ title: String) -> String {
    let text = " \(teletype(title)) ",
      stars = max(reportWidth - text.count, 2),
      leading = stars / 2
    return String(repeating: "*", count: leading) + text
      + String(repeating: "*", count: stars - leading)
  }

  private func table(
    columns: [TextColumn],
    rows: [(flagged: Bool, cells: [String])]
  ) -> [String] {
    [row(columns.map(\.heading), columns: columns, flagged: false)]
      + rows.map { row($0.cells, columns: columns, flagged: $0.flagged) }
  }

  private func row(_ cells: [String], columns: [TextColumn], flagged: Bool) -> String {
    zip(cells, columns).reduce(flagged ? "*" : " ") { line, entry in
      let (cell, column) = entry,
        text = teletype(cell),
        padding = String(repeating: " ", count: max(column.width - text.count, 1))
      return switch column.alignment {
        case .leading: line + " " + text + padding.dropFirst()
        case .trailing: line + padding + text
      }
    }
  }

  // MARK: - Values

  /// A distance and its margin as bare numbers, for two adjacent columns.
  func textDistance(_ value: Value<PerformanceDistance>?) -> (distance: String, margin: String) {
    guard let value, let distance = value.nominal else {
      let unavailable = value.flatMap { unavailableDescription(of: $0)?.text } ?? "-"
      return (unavailable, unavailable)
    }
    return (
      whole(distance.distance.converted(to: runwayLengthUnit).value),
      signed(distance.margin.converted(to: runwayLengthUnit).value)
    )
  }

  func textSpeed(_ value: Value<Measurement<UnitSpeed>>?) -> String {
    textValue(value) { whole($0.converted(to: speedUnit).value) }
  }

  func textBool(_ value: Value<Bool>?) -> String {
    textValue(value) { $0 ? "Y" : "N" }
  }

  func textValue<T>(_ value: Value<T>?, formatter: (T) -> String) -> String {
    guard let value else { return "-" }
    guard let unavailable = unavailableDescription(of: value) else {
      return value.nominal.map(formatter) ?? "-"
    }
    return unavailable.text
  }

  func whole(_ value: Double) -> String {
    String(Int(value.rounded()))
  }

  /// A fixed number of decimal places with a full stop, whatever the reader's locale uses.
  func decimal(_ value: Double, places: Int) -> String {
    String(format: "%.\(places)f", value)
  }

  /// The aircraft model as a fixed code. The app's own name is translated, and this is not.
  func textModel() -> String {
    switch input.aircraftType {
      case .g1: "SF50 G1"
      case .g2: "SF50 G2"
      case .g2Plus: "SF50 G2+"
    }
  }

  /// Weight limits as the codes a runway analysis uses: FL field length, O obstacle, C climb.
  /// The AFM chart's own limit keeps its name — the nearest standard code, ST, means a
  /// structural limit, which this is not.
  func textLimitingFactor(_ factor: LimitingFactor) -> String {
    switch factor {
      case .AFM: "AFM"
      case .field: "FL"
      case .obstacle: "O"
      case .climb: "C"
    }
  }

  /// Flap settings as fixed codes. The app's own names are translated, and this report is not.
  func textFlapSetting(_ setting: FlapSetting) -> String {
    switch setting {
      case .flapsUp: "UP"
      case .flapsUpIce: "UP ICE"
      case .flaps50: "50"
      case .flaps50Ice: "50 ICE"
      case .flaps100: "100"
    }
  }

  /// Runway condition as fixed codes, for the same reason. Depths are always inches, as they are
  /// everywhere else in the app, so the cell carries that unit itself.
  func textContamination(_ contamination: Contamination?) -> String {
    switch contamination {
      case .waterOrSlush(let depth):
        "WATER/SLUSH \(decimal(depth.converted(to: .inches).value, places: 2))IN"
      case .slushOrWetSnow(let depth):
        "SLUSH/WET SNOW \(decimal(depth.converted(to: .inches).value, places: 2))IN"
      case .drySnow: "DRY SNOW"
      case .compactSnow: "COMPACT SNOW"
      case .wetRunway: "WET"
      case .rwyCC(let code): "RWYCC \(code)"
      case nil: "DRY"
    }
  }

  func signed(_ value: Double) -> String {
    String(format: "%+d", Int(value.rounded()))
  }

  // MARK: - Teletype

  /// Zulu, as `ddhhmmZ`. An uplink never quotes local time, and a relayed report should not
  /// leave the recipient inferring a zone.
  ///
  /// Verbatim, with the calendar named and no locale attached, so the digits and the field order
  /// are the same for every reader.
  private func zulu(_ date: Date) -> String {
    date.formatted(
      .verbatim(
        "\(day: .twoDigits)\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased))\(minute: .twoDigits)Z",
        timeZone: .gmt,
        calendar: .init(identifier: .gregorian)
      )
    )
  }

  /// Folds text to what a teleprinter can carry: upper case, 7-bit ASCII, single-spaced.
  ///
  /// Scenario names are written by pilots, so they can hold anything at all. Typographic
  /// punctuation is transliterated rather than dropped, because a minus sign that vanishes turns
  /// a temperature or a weight into its opposite without looking wrong.
  private func teletype(_ text: String) -> String {
    let transliterated = Self.asciiEquivalents.reduce(text.uppercased()) { text, pair in
      text.replacingOccurrences(of: pair.key, with: pair.value)
    }
    let ascii = String(
      transliterated
        .folding(options: .diacriticInsensitive, locale: nil)
        .map { $0.isASCII ? $0 : " " }
    )
    return ascii.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
  }
}
