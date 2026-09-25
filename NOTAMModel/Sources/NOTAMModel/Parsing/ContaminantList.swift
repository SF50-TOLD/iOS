internal import Foundation

/// The contaminant list of an FAA FICON or Canadian RSC report: one list for the whole runway, or three
/// comma-separated lists, one per third in reporting order.
///
/// Each list is a series of contaminants joined by `AND`, each written
/// `[<n> PCT | PATCHY | THIN] [<depth>] <contaminant>`, among treatments, cleared widths, braking
/// action and snowbanks, which aren't recorded. `REMAINDER` ends a list: what lies outside the cleared
/// width isn't recorded either. `DRY` is a list with no contaminant. Any word the grammar doesn't know
/// makes the whole list unreadable.
enum ContaminantList {
  typealias Contaminant = NOTAMExtraction.Contaminant

  private static let thirdsPerRunway = 3
  private static var percentage: Regex<(Substring, Substring)> { /(\d{1,3})/ }
  private static var fractionalDepth: Regex<(Substring, Substring, Substring, Substring)> {
    /(\d+)\/(\d+)(IN|MM)/
  }
  private static var wholeDepth: Regex<(Substring, Substring, Substring)> {
    /(\d+(?:\.\d+)?)(IN|MM)/
  }
  private static var wholePart: Regex<(Substring, Substring)> { /(\d+)/ }
  private static var width: Regex<(Substring, Substring)> { /\d+(FT|M)/ }

  private static let unrecordedPhrases: [[String]] = [
    ["DEICED", "LIQUID"], ["DEICED", "SOLID"], ["DEICED"], ["SANDED"], ["SWEPT"], ["PLOWED"],
    ["TREATED"], ["CHEMICALLY", "TREATED"], ["WID"], ["WIDE"], ["SNOWBANKS"], ["BERMS"],
    ["WINDROWS"]
  ]
  private static let brakingActions = ["NIL", "POOR", "MEDIUM", "GOOD"]
  private static let banks = ["SNOWBANKS", "BERMS", "WINDROWS"]

  /// Reads a whole list, or returns `nil` if any of it is unreadable.
  static func parse(_ text: Substring) -> [Contaminant]? {
    let thirds = text.split(separator: ",", omittingEmptySubsequences: false)
    switch thirds.count {
      case 1:
        return parseThird(thirds[0], number: nil)
      case thirdsPerRunway:
        var contaminants: [Contaminant] = []
        for (offset, third) in thirds.enumerated() {
          guard let parsed = parseThird(third, number: offset + 1) else { return nil }
          contaminants += parsed
        }
        return contaminants
      default:
        return nil
    }
  }

  private static func parseThird(_ text: Substring, number: Int?) -> [Contaminant]? {
    var cursor = TokenCursor(text)
    var contaminants: [Contaminant] = [], isDry = false
    while !cursor.isAtEnd {
      skipUnrecorded(&cursor)
      if cursor.isAtEnd { break }
      if cursor.consume(["REMAINDER"]) {
        cursor.skipToEndOfThird()
        break
      }
      if var contaminant = readContaminant(&cursor) {
        contaminant.runwayThird = number
        contaminants.append(contaminant)
      } else if cursor.consume(ContaminantVocabulary.dry) {
        isDry = true
      } else {
        return nil
      }
    }
    switch (isDry, contaminants.isEmpty) {
      case (true, true): return []
      case (false, false): return contaminants
      default: return nil
    }
  }

  private static func readContaminant(_ cursor: inout TokenCursor) -> Contaminant? {
    let start = cursor
    let coveragePercent = readCoverage(&cursor)
    let depth = readDepth(&cursor)
    guard let type = ContaminantVocabulary.read(from: &cursor) else {
      cursor = start
      return nil
    }
    return Contaminant(type: type, runwayThird: nil, coveragePercent: coveragePercent, depth: depth)
  }

  /// The stated percentage. `PATCHY` and `THIN` are read but aren't percentages.
  private static func readCoverage(_ cursor: inout TokenCursor) -> Int? {
    if cursor.consume(["PATCHY"]) || cursor.consume(["THIN"]) { return nil }
    let start = cursor
    guard let match = cursor.consume(matching: percentage), cursor.consume(["PCT"]),
      let percent = Int(match.1), (0...100).contains(percent)
    else {
      cursor = start
      return nil
    }
    return percent
  }

  private static func readDepth(_ cursor: inout TokenCursor) -> NOTAMExtraction.Depth? {
    let start = cursor
    let whole = cursor.consume(matching: wholePart).flatMap { Double($0.1) } ?? 0
    if let fraction = cursor.consume(matching: fractionalDepth),
      let numerator = Double(fraction.1), let denominator = Double(fraction.2), denominator > 0
    {
      return depth(whole + numerator / denominator, unit: fraction.3)
    }
    cursor = start
    if let match = cursor.consume(matching: wholeDepth), let value = Double(match.1), value > 0 {
      return depth(value, unit: match.2)
    }
    cursor = start
    return nil
  }

  private static func depth(_ value: Double, unit: Substring) -> NOTAMExtraction.Depth {
    .init(value: value, unit: unit == "MM" ? .mm : .in)
  }

  private static func skipUnrecorded(_ cursor: inout TokenCursor) {
    while true {
      let start = cursor
      if cursor.consume(["AND"]) { continue }
      if unrecordedPhrases.contains(where: { cursor.consume($0) }) { continue }
      if cursor.consume(matching: width) != nil { continue }
      if cursor.consume(["BA"]) {
        guard readBrakingAction(&cursor) else {
          cursor = start
          return
        }
        continue
      }
      if readDepth(&cursor) != nil, let next = cursor.next, banks.contains(next) {
        cursor.advance()
        continue
      }
      cursor = start
      return
    }
  }

  private static func readBrakingAction(_ cursor: inout TokenCursor) -> Bool {
    guard let first = cursor.next, brakingActions.contains(first) else { return false }
    cursor.advance()
    if cursor.consume(["TO"]) {
      guard let second = cursor.next, brakingActions.contains(second) else { return false }
      cursor.advance()
    }
    return true
  }
}
