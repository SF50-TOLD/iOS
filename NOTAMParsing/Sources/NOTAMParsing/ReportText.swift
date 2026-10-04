internal import Foundation
internal import RegexBuilder

/// NOTAM text prepared for the formatted-report parsers: uppercased, on one line with single spaces.
///
/// Line wraps in NOTAM text fall between words wherever the line runs out, so the parsers read the
/// text as one line. An ICAO-format NOTAM (`Q) … A) … E) …`) is reduced to its `E)` field, the
/// only part that states the report.
struct ReportText {
  let text: String
}

/// Prepares NOTAM text for the parsers, and recognizes the words that keep a parser from reading it.
final class ReportScanner {
  /// Words that state a fact the formatted reports never carry. Where one of these appears in text
  /// a parser would otherwise ignore, that text states something the report's reading would drop.
  private static let performanceKeywords = [
    "CLSD", "CLOSED", "TORA", "TODA", "ASDA", "LDA", "DTHR", "DSPLCD", "DISPLACED", "RELOCATED",
    "THR", "OBST", "CRANE", "TWR", "NOT AVBL", "DECLARED"
  ]

  private let fieldE = Reference<Substring>()

  private lazy var ICAOFieldQ = Regex {
    Anchor.startOfLine
    ZeroOrMore(.whitespace)
    "Q)"
  }

  private lazy var ICAOFieldE = Regex {
    Anchor.wordBoundary
    "E)"
    ZeroOrMore(.whitespace)
    Capture(as: fieldE) { ZeroOrMore(.any, .reluctant) }
    ChoiceOf {
      Regex {
        OneOrMore(.whitespace)
        CharacterClass.anyOf("FG")
        ")"
        CharacterClass.whitespace
      }
      Anchor.endOfSubjectBeforeNewline
    }
  }

  private lazy var cancellation = Regex {
    Anchor.wordBoundary
    ChoiceOf {
      "NOTAMC"
      "CANCELED"
      "CANCELLED"
      "CNL"
    }
    Anchor.wordBoundary
  }

  private lazy var performanceKeyword = Regex {
    Anchor.wordBoundary
    ReportGrammar.alternation(of: Self.performanceKeywords)
    Anchor.wordBoundary
  }

  /// `notamText` prepared for the parsers.
  func text(of notamText: String) -> ReportText {
    var body = notamText[...]
    if notamText.contains(ICAOFieldQ), let match = notamText.firstMatch(of: ICAOFieldE) {
      body = match[fieldE]
    }
    return .init(
      text: body.uppercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    )
  }

  /// Whether the text shows a cancellation, which the parsers decline.
  func isCancellation(_ report: ReportText) -> Bool {
    report.text.contains(cancellation)
  }

  /// Whether ignorable text states something a parser would otherwise drop.
  func statesPerformanceFact(_ ignoredText: Substring) -> Bool {
    ignoredText.contains(performanceKeyword)
  }
}

extension Substring {
  /// The substring without its leading spaces.
  var droppingLeadingSpaces: Substring { drop { $0 == " " } }

  /// The substring without its trailing characters that satisfy `predicate`.
  func trimmingSuffix(while predicate: (Character) -> Bool) -> Substring {
    var result = self
    while let last = result.last, predicate(last) { result = result.dropLast() }
    return result
  }
}
