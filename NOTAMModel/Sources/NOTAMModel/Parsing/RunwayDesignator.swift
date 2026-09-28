/// Normalizes a runway designator to the schema's form: zero-padded, a pair written with a slash.
public enum RunwayDesignator {
  private static var direction: Regex<(Substring, Substring, Substring)> { /^(\d{1,2})([LCR]?)$/ }
  private static let minimumNumber = 1
  private static let maximumNumber = 36

  /// The schema form of `written` (`9R` → `09R`, `18C-36C` → `18C/36C`), or `nil` when it isn't a
  /// runway designator.
  public static func normalize(_ written: some StringProtocol) -> String? {
    let parts = String(written).split(separator: /[\/-]/, omittingEmptySubsequences: false)
    guard (1...2).contains(parts.count) else { return nil }
    let directions = parts.compactMap { normalizeDirection($0) }
    guard directions.count == parts.count else { return nil }
    return directions.joined(separator: "/")
  }

  /// The runway directions an effect's runway names: both directions of a pair (`09R/27L` →
  /// `09R`, `27L`), or the one direction; empty when it isn't a runway designator.
  ///
  /// - Parameter effectRunway: A ``NOTAMExtraction/RunwayEffect/runway``, in the schema's form.
  public static func directions(of effectRunway: String) -> [String] {
    normalize(effectRunway)?.split(separator: "/").map(String.init) ?? []
  }

  /// Whether an effect's runway names the runway direction `runwayName` (`9R` matches `09R/27L`).
  ///
  /// - Parameters:
  ///   - effectRunway: A ``NOTAMExtraction/RunwayEffect/runway``, in the schema's form.
  ///   - runwayName: A runway direction as written anywhere (`9R`, `09R`).
  public static func names(_ runwayName: String, in effectRunway: String) -> Bool {
    guard let direction = normalize(runwayName), !direction.contains("/") else { return false }
    return directions(of: effectRunway).contains(direction)
  }

  private static func normalizeDirection(_ written: Substring) -> String? {
    guard let match = try? direction.wholeMatch(in: written), let number = Int(match.1),
      (minimumNumber...maximumNumber).contains(number)
    else { return nil }
    let padded = number < 10 ? "0\(number)" : "\(number)"
    return padded + match.2
  }
}
