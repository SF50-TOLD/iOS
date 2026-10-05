internal import RegexBuilder

/// FAA FICON runway condition reports (FAA JO 7930.2): `[<id>] RWY <rwy> FICON [n/n/n] <list> OBS AT
/// <time>.`, one or more per NOTAM. A FICON for a taxiway or apron states nothing about a runway, so
/// it reads as no effects.
final class FICONReport: ReportFormat {
  private let runway = Reference<Substring>()
  private let body = Reference<Substring>()
  private let codes = Reference<[Int]?>()
  private let list = Reference<Substring>()

  private let scanner: ReportScanner, contaminantList: ContaminantList

  /// The aerodrome identifier that may open the NOTAM, before its first runway report.
  private lazy var identifier = Regex {
    Repeat(3...4) { ReportGrammar.alphanumeric }
    " "
    Lookahead { "RWY " }
  }

  private lazy var runwayReport = Regex {
    "RWY "
    Capture(as: runway) { ReportGrammar.word }
    " FICON "
    Capture(as: body) { OneOrMore(.any, .reluctant) }
    " OBS AT "
    Repeat(ReportGrammar.digit, count: 10)
    Optionally(".")
  }

  private lazy var reportBody = Regex {
    Optionally {
      Capture(as: codes) {
        RunwayConditionCodes.pattern
      } transform: {
        RunwayConditionCodes.values(of: $0)
      }
      " "
    }
    Capture(as: list) { OneOrMore(.any) }
  }

  private lazy var movementAreaReport = Regex {
    Optionally {
      Repeat(3...4) { ReportGrammar.alphanumeric }
      " "
    }
    ChoiceOf {
      "TWY"
      "TWYS"
      "APRON"
      "APN"
      "RAMP"
    }
    Anchor.wordBoundary
    textWithoutRunway
    Anchor.wordBoundary
    "FICON"
    Anchor.wordBoundary
    textWithoutRunway
  }

  private lazy var textWithoutRunway = Regex {
    ZeroOrMore {
      NegativeLookahead {
        Anchor.wordBoundary
        "RWY"
        Anchor.wordBoundary
      }
      CharacterClass.any
    }
  }

  private lazy var validity = Regex {
    Repeat(ReportGrammar.digit, count: 10)
    "-"
    Repeat(ReportGrammar.digit, count: 10)
    Optionally("EST")
  }

  init(scanner: ReportScanner, contaminantList: ContaminantList) {
    self.scanner = scanner
    self.contaminantList = contaminantList
  }

  func parse(_ report: ReportText) -> FormattedReport? {
    let text = withoutValidity(report.text)
    if text.wholeMatch(of: movementAreaReport) != nil, !scanner.statesPerformanceFact(text) {
      return .init(effects: [])
    }
    return parseRunwayReports(text)
  }

  private func parseRunwayReports(_ text: Substring) -> FormattedReport? {
    var remainder = text
    if let match = remainder.prefixMatch(of: identifier) {
      remainder = remainder[match.range.upperBound...]
    }
    var effects: [FormattedReport.RunwayEffect] = []
    while !remainder.isEmpty {
      guard let match = remainder.prefixMatch(of: runwayReport),
        let effect = effect(runway: match[runway], body: match[body])
      else { return nil }
      effects.append(effect)
      remainder = remainder[match.range.upperBound...].droppingLeadingSpaces
    }
    return effects.isEmpty ? nil : FormattedReport.mergingRepeatedReports(effects)
  }

  private func effect(runway written: Substring, body: Substring) -> FormattedReport.RunwayEffect? {
    guard let runway = RunwayDesignator.normalize(written),
      let match = body.wholeMatch(of: reportBody),
      let contaminants = contaminantList.parse(match[list])
    else { return nil }
    return .surfaceCondition(runway: runway, rwyCC: match[codes], contaminants: contaminants)
  }

  private func withoutValidity(_ text: String) -> Substring {
    guard let match = text.firstMatch(of: validity), match.range.upperBound == text.endIndex else {
      return text[...]
    }
    return text[..<match.range.lowerBound].trimmingSuffix(while: { $0 == " " })
  }
}
