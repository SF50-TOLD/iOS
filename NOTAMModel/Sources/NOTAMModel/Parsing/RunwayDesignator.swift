/// Normalizes a runway designator to the schema's form: zero-padded, a pair written with a slash.
enum RunwayDesignator {
  private static var direction: Regex<(Substring, Substring, Substring)> { /^(\d{1,2})([LCR]?)$/ }
  private static let minimumNumber = 1
  private static let maximumNumber = 36

  /// The schema form of `written` (`9R` → `09R`, `18C-36C` → `18C/36C`), or `nil` when it isn't a
  /// runway designator.
  static func normalize(_ written: some StringProtocol) -> String? {
    let parts = String(written).split(separator: /[\/-]/, omittingEmptySubsequences: false)
    guard (1...2).contains(parts.count) else { return nil }
    let directions = parts.compactMap { normalizeDirection($0) }
    guard directions.count == parts.count else { return nil }
    return directions.joined(separator: "/")
  }

  private static func normalizeDirection(_ written: Substring) -> String? {
    guard let match = try? direction.wholeMatch(in: written), let number = Int(match.1),
      (minimumNumber...maximumNumber).contains(number)
    else { return nil }
    let padded = number < 10 ? "0\(number)" : "\(number)"
    return padded + match.2
  }
}
