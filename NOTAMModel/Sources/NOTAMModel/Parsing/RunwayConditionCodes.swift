/// The `n/n/n` runway condition codes that open a FICON, RSC or SNOWTAM runway report.
enum RunwayConditionCodes {
  private static var codes: Regex<(Substring, Substring, Substring, Substring)> {
    /([0-6])\/([0-6])\/([0-6])/
  }

  /// The codes in `token`, in reporting order, or `nil` when it isn't a set of codes.
  static func parse(_ token: some StringProtocol) -> [Int]? {
    guard let match = try? codes.wholeMatch(in: String(token)) else { return nil }
    return [match.1, match.2, match.3].compactMap { Int($0) }
  }
}
