/// Canadian RSC runway surface condition reports: an optional aerodrome line, one `RSC <rwy> [n/n/n]
/// <list>. <remarks>.` report per runway, then optional non-GRF information and remarks.
///
/// The list follows the FICON grammar. Only remarks known to state nothing the schema records — the
/// validity period, RWYCC downgrades, chemical residue, cleared widths, windrows, work in progress — may
/// follow it. The non-GRF section (CRFI, taxiway and apron remarks) isn't recorded.
enum RSCReport {
  private static var reportStart: Regex<Substring> { /\bRSC (?=\S+ )/ }
  private static var addendumStart: Regex<Substring> { /\bADDN NON-GRF\/TALPA INFO:|\bRMK:/ }
  private static let maximumPreambleLength = 80

  private static var ignorableClauses: [Regex<Substring>] {
    [
      /VALID .+/,
      /(?:TOUCHDOWN|MIDPOINT|ROLLOUT|ALL) RWYCC DOWNGRADED/,
      /CHEMICAL RESIDUE PRESENT/,
      /RESIDUAL CHEMICAL PRESENT/,
      /FORMATE RESIDUE/,
      /LOOSE SAND APPLIED/,
      /UREA TREATED(?: .+)?/,
      /CRFI N\/R/,
      /TURN AND TAXI WITH CAUTION/,
      /CHEMICAL(?:LY)? (?:APPLIED|REAPPLIED|TREATED)/,
      /SLIPPERY CONDITIONS(?: ON TAXIWAYS| HIGH SPEED EXITS)?/,
      /PATCHY CONTAMINANT/,
      /(?:CLEARING\/SWEEPING|CLEARING|SWEEPING|SANDING|PLOWING|SNOW REMOVAL) IN PROGRESS/,
      /(?:RUNWAY SURFACE )?(?:GRADED|SANDED|SCARIFIED)/,
      /\d+(?:FT|M) WIDTH/,
      /(?:\d+(?:FT|IN) )?WINDROWS(?: .+)?/,
      /REMAINING WIDTH .+/,
      /SNOW DRIFTS ON RUNWAY/,
      /RUNWAY SNOW GRAVEL MIX/,
      /NEXT OBS AT .+/
    ]
  }

  static func parse(_ report: ReportText) -> NOTAMExtraction? {
    let text = report.text[...]
    let addendum = text.firstMatch(of: addendumStart)
    let main = addendum.map { text[..<$0.range.lowerBound] } ?? text
    if let addendum, ReportText.statesPerformanceFact(text[addendum.range.lowerBound...]) {
      return nil
    }

    let starts = main.matches(of: reportStart).map(\.range)
    guard let first = starts.first, isIgnorablePreamble(main[..<first.lowerBound]) else {
      return nil
    }
    var effects: [NOTAMExtraction.RunwayEffect] = []
    for (index, start) in starts.enumerated() {
      let end = index + 1 < starts.count ? starts[index + 1].lowerBound : main.endIndex
      guard let effect = effect(main[start.upperBound..<end]) else { return nil }
      effects.append(effect)
    }
    return NOTAMExtraction.mergingRepeatedReports(effects)
  }

  private static func isIgnorablePreamble(_ preamble: Substring) -> Bool {
    preamble.count <= maximumPreambleLength && !preamble.contains("RWY")
      && !ReportText.statesPerformanceFact(preamble)
  }

  private static func effect(_ report: Substring) -> NOTAMExtraction.RunwayEffect? {
    var words = report.split(separator: " ", maxSplits: 1)
    guard words.count == 2, let runway = RunwayDesignator.normalize(words[0]) else { return nil }
    let rwyCC = words[1].split(separator: " ", maxSplits: 1).first.flatMap(
      RunwayConditionCodes.parse
    )
    if rwyCC != nil { words = words[1].split(separator: " ", maxSplits: 1) }
    guard words.count == 2 else { return nil }

    let sentences = words[1].trimmingSuffix(while: { $0 == " " || $0 == "." }).split(
      separator: ". "
    )
    guard let list = sentences.first, let contaminants = ContaminantList.parse(list),
      sentences.dropFirst().allSatisfy(isIgnorableRemark)
    else { return nil }
    return .surfaceCondition(runway: runway, rwyCC: rwyCC, contaminants: contaminants)
  }

  private static func isIgnorableRemark(_ sentence: Substring) -> Bool {
    sentence.split(separator: ", ").allSatisfy { clause in
      !ReportText.statesPerformanceFact(clause)
        && ignorableClauses.contains { (try? $0.wholeMatch(in: String(clause))) != nil }
    }
  }
}
