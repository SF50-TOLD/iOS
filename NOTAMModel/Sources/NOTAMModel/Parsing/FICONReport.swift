/// FAA FICON runway condition reports (FAA JO 7930.2): `[<id>] RWY <rwy> FICON [n/n/n] <list> OBS AT
/// <time>.`, one or more per NOTAM. A FICON for a taxiway or apron states nothing about a runway, so
/// it reads as no effects.
enum FICONReport {
  private static var identifier: Regex<Substring> { /[A-Z0-9]{3,4}/ }
  private static var runwayReport: Regex<(Substring, Substring, Substring)> {
    /RWY (\S+) FICON (.+?) OBS AT \d{10}\.?/
  }
  private static var movementAreaReport: Regex<Substring> {
    /(?:[A-Z0-9]{3,4} )?(?:TWY|TWYS|APRON|APN|RAMP)\b(?:(?!\bRWY\b).)*\bFICON\b(?:(?!\bRWY\b).)*/
  }
  private static var validity: Regex<Substring> { /\d{10}-\d{10}(?:EST)?/ }

  static func parse(_ report: ReportText) -> NOTAMExtraction? {
    let text = withoutValidity(report.text)
    if (try? movementAreaReport.wholeMatch(in: text)) != nil,
      !ReportText.statesPerformanceFact(text)
    {
      return .init(isCanceled: false, effects: [])
    }
    return parseRunwayReports(text)
  }

  private static func parseRunwayReports(_ text: Substring) -> NOTAMExtraction? {
    var remainder = text
    if let prefix = remainder.prefixMatch(of: identifier),
      remainder.dropFirst(prefix.count).hasPrefix(" RWY ")
    {
      remainder = remainder.dropFirst(prefix.count + 1)
    }
    var effects: [NOTAMExtraction.RunwayEffect] = []
    while !remainder.isEmpty {
      guard let match = remainder.prefixMatch(of: runwayReport),
        let effect = effect(runway: match.1, body: match.2)
      else { return nil }
      effects.append(effect)
      remainder = remainder.dropFirst(match.0.count).drop(while: { $0 == " " })
    }
    return effects.isEmpty ? nil : NOTAMExtraction.mergingRepeatedReports(effects)
  }

  private static func effect(runway written: Substring, body: Substring) -> NOTAMExtraction
    .RunwayEffect?
  {
    guard let runway = RunwayDesignator.normalize(written) else { return nil }
    let firstWord = body.prefix { $0 != " " }
    let rwyCC = RunwayConditionCodes.parse(firstWord)
    let list = rwyCC == nil ? body : body.dropFirst(firstWord.count).drop(while: { $0 == " " })
    guard let contaminants = ContaminantList.parse(list) else { return nil }
    return .surfaceCondition(runway: runway, rwyCC: rwyCC, contaminants: contaminants)
  }

  private static func withoutValidity(_ text: String) -> Substring {
    guard let match = text.firstMatch(of: validity), match.range.upperBound == text.endIndex else {
      return text[...]
    }
    return text[..<match.range.lowerBound].trimmingSuffix(while: { $0 == " " })
  }
}
