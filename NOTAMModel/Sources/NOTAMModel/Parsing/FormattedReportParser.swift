/**
 Reads the NOTAMs whose text follows a fixed report format — FAA FICON, Canadian RSC and ICAO SNOWTAM
 runway condition reports, and FAA obstacle reports — exactly, without a model.

 A parser either reads the whole NOTAM or declines it. It never returns a partial reading: text it
 doesn't understand, a cancellation, or ignorable text that states a closure, declared distance,
 threshold or obstacle all make it return `nil`, so the NOTAM goes to a full reading instead.
 */
public enum FormattedReportParser {
  private static let formats: [@Sendable (ReportText) -> NOTAMExtraction?] = [
    SNOWTAMReport.parse, RSCReport.parse, FICONReport.parse, FAAObstacleReport.parse
  ]

  /// Reads a formatted report, or returns `nil` when the NOTAM isn't one this parser reads whole.
  ///
  /// - Parameter notamText: The NOTAM text as the NOTAM API returns it.
  /// - Returns: The extraction, or `nil` to decline.
  public static func parse(notamText: String) -> NOTAMExtraction? {
    let text = ReportText(notamText)
    guard !text.isCancellation else { return nil }
    return formats.lazy.compactMap { $0(text) }.first
  }
}

extension NOTAMExtraction {
  /// An extraction of one report per runway, with a report repeated word for word stated once; `nil`
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
    return .init(isCanceled: false, effects: merged)
  }
}

extension NOTAMExtraction.RunwayEffect {
  /// An effect that states only a runway's surface condition.
  static func surfaceCondition(
    runway: String,
    rwyCC: [Int]?,
    contaminants: [NOTAMExtraction.Contaminant]
  ) -> Self {
    .init(
      runway: runway,
      closure: .none,
      closedLength: nil,
      closedEnd: nil,
      thresholdDisplacement: nil,
      declaredDistances: nil,
      surfaceCondition: .init(rwyCC: rwyCC, contaminants: contaminants),
      obstacle: nil
    )
  }
}
