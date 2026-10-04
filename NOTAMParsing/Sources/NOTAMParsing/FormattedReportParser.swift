/**
 Reads the NOTAMs whose text follows a fixed report format — FAA FICON, Canadian RSC and ICAO SNOWTAM
 runway condition reports, and FAA obstacle reports — exactly.

 A parser either reads the whole NOTAM or declines it. It never returns a partial reading: text it
 doesn't understand, a cancellation, or ignorable text that states a closure, declared distance,
 threshold or obstacle all make it return `nil`, leaving the NOTAM for the pilot to read.

 Each format's grammar is built once per parser, so read a batch of NOTAMs with one parser.
 */
public final class FormattedReportParser {
  private let scanner: ReportScanner
  private let formats: [any ReportFormat]

  /// Creates a parser.
  public init() {
    let scanner = ReportScanner(),
      vocabulary = ContaminantVocabulary(),
      contaminantList = ContaminantList(vocabulary: vocabulary)
    self.scanner = scanner
    formats = [
      SNOWTAMReport(scanner: scanner, vocabulary: vocabulary),
      RSCReport(scanner: scanner, contaminantList: contaminantList),
      FICONReport(contaminantList: contaminantList),
      FAAObstacleReport()
    ]
  }

  /// Reads a formatted report, or returns `nil` when the NOTAM isn't one this parser reads whole.
  ///
  /// - Parameter notamText: The NOTAM text as the NOTAM API returns it.
  /// - Returns: The report, or `nil` to decline.
  public func parse(notamText: String) -> FormattedReport? {
    let report = scanner.text(of: notamText)
    guard !scanner.isCancellation(report) else { return nil }
    return formats.lazy.compactMap { $0.parse(report) }.first
  }
}

/// One fixed report format.
protocol ReportFormat {
  /// Reads `report` whole, or returns `nil` when it isn't in this format.
  func parse(_ report: ReportText) -> FormattedReport?
}

extension FormattedReport {
  /// A report of one effect per runway, with a report repeated word for word stated once; `nil`
  /// when two reports for the same runway differ.
  static func mergingRepeatedReports(_ effects: [RunwayEffect]) -> Self? {
    var merged: [RunwayEffect] = []
    for effect in effects {
      if let earlier = merged.first(where: { $0.runway == effect.runway }) {
        guard earlier == effect else { return nil }
      } else {
        merged.append(effect)
      }
    }
    return .init(effects: merged)
  }
}

extension FormattedReport.RunwayEffect {
  /// An effect that states only a runway's surface condition.
  static func surfaceCondition(
    runway: String,
    rwyCC: [Int]?,
    contaminants: [FormattedReport.Contaminant]
  ) -> Self {
    .init(runway: runway, surfaceCondition: .init(rwyCC: rwyCC, contaminants: contaminants))
  }
}
