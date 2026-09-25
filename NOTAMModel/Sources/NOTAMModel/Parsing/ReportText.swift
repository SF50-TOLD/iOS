internal import Foundation

/// NOTAM text prepared for the formatted-report parsers.
///
/// Line wraps in NOTAM text fall between words wherever the line runs out, so the parsers read the
/// text as one line with single spaces. An ICAO-format NOTAM (`Q) … A) … E) …`) is reduced to its
/// `E)` field, the only part that states the report.
struct ReportText {
  private static var ICAOFieldE: Regex<(Substring, Substring)> {
    /(?s)\bE\)\s*(.*?)(?:\s+[FG]\)\s|$)/
  }
  private static var ICAOFieldQ: Regex<Substring> { /(?m)^\s*Q\)/ }

  /// The text, uppercased, on one line with single spaces.
  let text: String

  init(_ notamText: String) {
    var body = notamText
    if notamText.contains(Self.ICAOFieldQ),
      let fieldE = try? Self.ICAOFieldE.firstMatch(in: notamText)
    {
      body = String(fieldE.1)
    }
    text = body.uppercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
  }
}

extension ReportText {
  private static var cancellation: Regex<(Substring, Substring)> {
    /\b(NOTAMC|CANCELED|CANCELLED|CNL)\b/
  }

  /// Words that state a fact the formatted reports never carry. Where one of these appears in text
  /// a parser would otherwise ignore, that text is stating something only a full reading can capture.
  private static var performanceKeyword: Regex<(Substring, Substring)> {
    /\b(CLSD|CLOSED|TORA|TODA|ASDA|LDA|DTHR|DSPLCD|DISPLACED|RELOCATED|THR|OBST|CRANE|TWR|NOT AVBL|DECLARED)\b/
  }

  /// Whether the text shows a cancellation, which the parsers leave to a full reading.
  var isCancellation: Bool { text.contains(Self.cancellation) }

  /// Whether ignorable text states something a parser would otherwise drop.
  static func statesPerformanceFact(_ ignoredText: some StringProtocol) -> Bool {
    String(ignoredText).contains(performanceKeyword)
  }
}

extension Substring {
  /// The substring without its trailing characters that satisfy `predicate`.
  func trimmingSuffix(while predicate: (Character) -> Bool) -> Substring {
    var result = self
    while let last = result.last, predicate(last) { result = result.dropLast() }
    return result
  }
}
