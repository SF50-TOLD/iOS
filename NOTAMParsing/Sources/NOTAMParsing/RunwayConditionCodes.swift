internal import RegexBuilder

/// The `n/n/n` runway condition codes that open a FICON, RSC or SNOWTAM runway report.
enum RunwayConditionCodes {
  /// Three codes from 0 to 6, separated by slashes.
  static var pattern: Regex<Substring> {
    Regex {
      code
      "/"
      code
      "/"
      code
    }
  }

  private static var code: CharacterClass { CharacterClass("0"..."6") }

  /// The codes in text `pattern` matched, in reporting order.
  static func values(of codes: Substring) -> [Int] {
    codes.split(separator: "/").compactMap { Int($0) }
  }
}
