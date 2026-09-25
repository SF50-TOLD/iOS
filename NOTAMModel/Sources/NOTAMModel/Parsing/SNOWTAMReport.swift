/// ICAO SNOWTAMs in the Global Reporting Format: a header, then one runway condition line per runway,
/// `<observed> <rwy> <n/n/n> <cov/cov/cov> <depth/depth/depth> <condition/condition/condition>`, then
/// optional situational-awareness remarks, which aren't recorded.
///
/// Every field is given per third. The format defines coverage as a percentage and depth in
/// millimetres; `NR` is not reported, and a `DRY` or `NR` third has no contaminant.
enum SNOWTAMReport {
  private static var header: Regex<Substring> {
    #/SW[A-Z]{2}\d{4} [A-Z]{4} \d{8} \( SNOWTAM \d{1,4} [A-Z]{4} /#
  }
  private static var observationTime: Regex<Substring> { /\d{8}/ }
  private static var coverage: Regex<Substring> { /\d{1,3}/ }
  private static var depth: Regex<Substring> { /\d{1,3}/ }
  private static var clearedWidth: Regex<Substring> { /\d{2,3}/ }
  private static let notReported = "NR"
  private static let thirdsPerRunway = 3

  static func parse(_ report: ReportText) -> NOTAMExtraction? {
    let spaced = report.text.replacing("(", with: "( ").replacing(")", with: " )")
    guard let headerMatch = spaced.prefixMatch(of: header),
      let close = spaced.lastIndex(of: ")"),
      spaced[spaced.index(after: close)...].allSatisfy(\.isWhitespace)
    else { return nil }

    var cursor = TokenCursor(
      spaced[headerMatch.range.upperBound..<close].replacing("/", with: " / ")
    )
    var effects: [NOTAMExtraction.RunwayEffect] = []
    while cursor.consume(matching: observationTime) != nil {
      guard let effect = readRunwayLine(&cursor) else { return nil }
      effects.append(effect)
    }
    guard !effects.isEmpty, !ReportText.statesPerformanceFact(cursor.remainder) else { return nil }
    return NOTAMExtraction.mergingRepeatedReports(effects)
  }

  private static func readRunwayLine(_ cursor: inout TokenCursor) -> NOTAMExtraction.RunwayEffect? {
    guard let written = cursor.next, let runway = RunwayDesignator.normalize(written) else {
      return nil
    }
    cursor.advance()
    guard let codes = readPerThird(&cursor, read: readCode),
      let coverages = readPerThird(&cursor, read: { readReported(&$0, pattern: coverage) }),
      let depths = readPerThird(&cursor, read: { readReported(&$0, pattern: depth) }),
      let conditions = readPerThird(&cursor, read: readCondition)
    else { return nil }
    _ = cursor.consume(matching: clearedWidth)

    let contaminants = (0..<thirdsPerRunway).compactMap { index in
      contaminant(
        third: index + 1,
        condition: conditions[index],
        coveragePercent: coverages[index],
        depthMM: depths[index]
      )
    }
    guard coverages.allSatisfy({ ($0 ?? 0) <= 100 }) else { return nil }
    return .surfaceCondition(
      runway: runway,
      rwyCC: codes.compactMap(\.self),
      contaminants: contaminants
    )
  }

  private static func contaminant(
    third: Int,
    condition: NOTAMExtraction.ContaminantType?,
    coveragePercent: Int?,
    depthMM: Int?
  ) -> NOTAMExtraction.Contaminant? {
    guard let condition else { return nil }
    return .init(
      type: condition,
      runwayThird: third,
      coveragePercent: coveragePercent,
      depth: depthMM.flatMap { $0 > 0 ? .init(value: Double($0), unit: .mm) : nil }
    )
  }

  /// Reads three slash-separated values, or `nil` if any is unreadable.
  private static func readPerThird<Value>(
    _ cursor: inout TokenCursor,
    read: (inout TokenCursor) -> Value??
  ) -> [Value?]? {
    var values: [Value?] = []
    for index in 0..<thirdsPerRunway {
      if index > 0, !cursor.consume(["/"]) { return nil }
      guard let value = read(&cursor) else { return nil }
      values.append(value)
    }
    return values
  }

  private static func readCode(_ cursor: inout TokenCursor) -> Int?? {
    guard let next = cursor.next, let code = Int(next), (0...6).contains(code) else { return nil }
    cursor.advance()
    return .some(code)
  }

  /// A reported number, `.some(nil)` for `NR`, or `nil` when unreadable.
  private static func readReported(_ cursor: inout TokenCursor, pattern: Regex<Substring>) -> Int??
  {
    if cursor.consume([notReported]) { return .some(nil) }
    guard let match = cursor.consume(matching: pattern), let value = Int(match) else { return nil }
    return .some(value)
  }

  /// A contaminant, `.some(nil)` for `DRY` or `NR`, or `nil` when unreadable.
  private static func readCondition(_ cursor: inout TokenCursor) -> NOTAMExtraction
    .ContaminantType??
  {
    if let type = ContaminantVocabulary.read(from: &cursor) { return .some(type) }
    if cursor.consume(ContaminantVocabulary.dry) || cursor.consume([notReported]) {
      return .some(nil)
    }
    return nil
  }
}
