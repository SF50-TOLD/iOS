internal import Foundation
internal import RegexBuilder

/// ICAO SNOWTAMs in the Global Reporting Format: a header, then one runway condition line per runway,
/// `<observed> <rwy> <n/n/n> <cov/cov/cov> <depth/depth/depth> <condition/condition/condition>`, then
/// optional situational-awareness remarks, which aren't recorded.
///
/// Every field is given per third. The format defines coverage as a percentage and depth in
/// millimetres; `NR` is not reported, and a `DRY` or `NR` third has no contaminant.
final class SNOWTAMReport: ReportFormat {
  typealias ContaminantType = FormattedReport.ContaminantType

  private static let maximumPercent = 100
  private static let notReported = "NR", dry = "DRY"
  private static let conditionCodes = 0...6

  private let body = Reference<Substring>()
  private let runway = Reference<Substring>()
  private let codes = Reference<[Int]>()
  private let coverages = Reference<[Int?]>()
  private let depths = Reference<[Int?]>()
  private let conditions = Reference<[Substring]>()

  private let scanner: ReportScanner, vocabulary: ContaminantVocabulary

  /// The header and the closing parenthesis around the runway lines and remarks.
  private lazy var snowtam = Regex {
    "SW"
    Repeat(count: 2) { ReportGrammar.letter }
    Repeat(ReportGrammar.digit, count: 4)
    " "
    Repeat(count: 4) { ReportGrammar.letter }
    " "
    Repeat(ReportGrammar.digit, count: 8)
    " (SNOWTAM "
    Repeat(ReportGrammar.digit, 1...4)
    " "
    Repeat(count: 4) { ReportGrammar.letter }
    " "
    Capture(as: body) { ZeroOrMore(.any) }
    ")"
    ZeroOrMore(.whitespace)
  }

  private lazy var observationTime = Regex {
    Repeat(ReportGrammar.digit, count: 8)
    ReportGrammar.tokenEnd
  }

  private lazy var runwayLine = Regex {
    observationTime
    " "
    Capture(as: runway) { OneOrMore(CharacterClass.anyOf(" /,").inverted) }
    " "
    TryCapture(as: codes) {
      Self.perThird(OneOrMore(ReportGrammar.digit))
    } transform: {
      let codes = Self.thirds(of: $0).compactMap { Int($0) }
      return codes.allSatisfy(Self.conditionCodes.contains) ? codes : nil
    }
    " "
    Capture(as: coverages) {
      Self.perThird(reported)
    } transform: {
      Self.reportedValues(of: $0)
    }
    " "
    Capture(as: depths) {
      Self.perThird(reported)
    } transform: {
      Self.reportedValues(of: $0)
    }
    " "
    Capture(as: conditions) {
      Self.perThird(condition)
    } transform: {
      Self.thirds(of: $0)
    }
    Optionally {
      " "
      Repeat(ReportGrammar.digit, 2...3)
      ReportGrammar.tokenEnd
    }
  }

  /// A number, or `NR` for not reported.
  private lazy var reported = Regex {
    ChoiceOf {
      Self.notReported
      Repeat(ReportGrammar.digit, 1...3)
    }
  }

  /// A contaminant, or `DRY` or `NR` for none.
  private lazy var condition = Regex {
    ChoiceOf {
      vocabulary.phrase
      Self.dry
      Self.notReported
    }
    ReportGrammar.tokenEnd
  }

  init(scanner: ReportScanner, vocabulary: ContaminantVocabulary) {
    self.scanner = scanner
    self.vocabulary = vocabulary
  }

  /// `value` three times, separated by slashes.
  private static func perThird(_ value: some RegexComponent<Substring>) -> Regex<Substring> {
    let separator = Regex {
      Optionally(" ")
      "/"
      Optionally(" ")
    }
    return Regex {
      value
      separator
      value
      separator
      value
    }
  }

  /// The three values text `perThird(_:)` matched.
  private static func thirds(of text: Substring) -> [Substring] {
    text.split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces)[...] }
  }

  /// Each third's number, `nil` for `NR`.
  private static func reportedValues(of text: Substring) -> [Int?] {
    thirds(of: text).map { Int($0) }
  }

  func parse(_ report: ReportText) -> FormattedReport? {
    guard let match = report.text.wholeMatch(of: snowtam) else { return nil }
    var rest = match[body], effects: [FormattedReport.RunwayEffect] = []
    while rest.prefixMatch(of: observationTime) != nil {
      guard let line = rest.prefixMatch(of: runwayLine), let effect = effect(from: line) else {
        return nil
      }
      effects.append(effect)
      rest = rest[line.range.upperBound...].droppingLeadingSpaces
    }
    guard !effects.isEmpty, !scanner.statesPerformanceFact(rest) else { return nil }
    return FormattedReport.mergingRepeatedReports(effects)
  }

  private func effect<Output>(from line: Regex<Output>.Match) -> FormattedReport.RunwayEffect? {
    let coveragePercents = line[coverages], depthsMM = line[depths]
    guard let runway = RunwayDesignator.normalize(line[runway]),
      let types = contaminantTypes(in: line),
      coveragePercents.allSatisfy({ ($0 ?? 0) <= Self.maximumPercent })
    else { return nil }
    let contaminants = types.indices.compactMap { index -> FormattedReport.Contaminant? in
      guard let type = types[index] else { return nil }
      return .init(
        type: type,
        runwayThird: index + 1,
        coveragePercent: coveragePercents[index],
        depth: depthsMM[index].flatMap {
          $0 > 0 ? .init(value: Double($0), unit: .millimeters) : nil
        }
      )
    }
    return .surfaceCondition(runway: runway, rwyCC: line[codes], contaminants: contaminants)
  }

  /// Each third's contaminant, `nil` for `DRY` and `NR`; `nil` when a third's isn't one the
  /// vocabulary names.
  private func contaminantTypes<Output>(in line: Regex<Output>.Match) -> [ContaminantType?]? {
    var types: [ContaminantType?] = []
    for condition in line[conditions] {
      if condition == Self.dry || condition == Self.notReported {
        types.append(nil)
        continue
      }
      guard let type = ContaminantVocabulary.type(of: condition) else { return nil }
      types.append(type)
    }
    return types
  }
}
