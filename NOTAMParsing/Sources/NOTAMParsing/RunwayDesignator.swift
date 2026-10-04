internal import RegexBuilder

/// Normalizes a runway designator to the form reports are recorded in: zero-padded, a pair written
/// with a slash.
public enum RunwayDesignator {
  private static let numbers = 1...36

  private static var direction: Regex<(Substring, Int)> {
    Regex {
      TryCapture {
        Repeat(ReportGrammar.digit, 1...2)
      } transform: {
        Int($0).flatMap { numbers.contains($0) ? $0 : nil }
      }
      Optionally(CharacterClass.anyOf("LCR"))
    }
  }

  /// The normalized form of `written` (`9R` → `09R`, `18C-36C` → `18C/36C`), or `nil` when it
  /// isn't a runway designator.
  public static func normalize(_ written: some StringProtocol) -> String? {
    let parts = written.split(omittingEmptySubsequences: false) { $0 == "/" || $0 == "-" }
    guard (1...2).contains(parts.count) else { return nil }
    let directions = parts.compactMap { normalizeDirection(Substring($0)) }
    guard directions.count == parts.count else { return nil }
    return directions.joined(separator: "/")
  }

  /// The runway directions an effect's runway names: both directions of a pair (`09R/27L` →
  /// `09R`, `27L`), or the one direction; empty when it isn't a runway designator.
  ///
  /// - Parameter effectRunway: A ``FormattedReport/RunwayEffect/runway``, normalized.
  public static func directions(of effectRunway: String) -> [String] {
    normalize(effectRunway)?.split(separator: "/").map(String.init) ?? []
  }

  /// Whether an effect's runway names the runway direction `runwayName` (`9R` matches `09R/27L`).
  ///
  /// - Parameters:
  ///   - runwayName: A runway direction as written anywhere (`9R`, `09R`).
  ///   - effectRunway: A ``FormattedReport/RunwayEffect/runway``, normalized.
  public static func names(_ runwayName: String, in effectRunway: String) -> Bool {
    guard let direction = normalize(runwayName), !direction.contains("/") else { return false }
    return directions(of: effectRunway).contains(direction)
  }

  private static func normalizeDirection(_ written: Substring) -> String? {
    guard let match = written.wholeMatch(of: direction) else { return nil }
    let (direction, number) = match.output, side = direction.drop(while: \.isNumber)
    return (number < 10 ? "0\(number)" : "\(number)") + side
  }
}
