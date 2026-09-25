/// A position in a report's words, read left to right.
///
/// Commas are their own tokens so a report's thirds can be told apart. It's a value type, so a parser
/// backtracks by keeping a copy.
struct TokenCursor {
  private let tokens: [String]
  private var index = 0

  var isAtEnd: Bool { index == tokens.count }
  var next: String? { isAtEnd ? nil : tokens[index] }

  /// The words not yet read, joined by spaces.
  var remainder: String { tokens[index...].joined(separator: " ") }

  init(_ text: some StringProtocol) {
    tokens = String(text).replacing(",", with: " , ").split(separator: " ").map(String.init)
  }

  func hasPrefix(_ words: [String]) -> Bool {
    tokens.count - index >= words.count && Array(tokens[index..<index + words.count]) == words
  }

  mutating func advance(by count: Int = 1) {
    index = min(index + count, tokens.count)
  }

  /// Reads `words` if the cursor is at them.
  mutating func consume(_ words: [String]) -> Bool {
    guard hasPrefix(words) else { return false }
    advance(by: words.count)
    return true
  }

  /// Reads the next token if it matches `pattern`, returning the match.
  mutating func consume<Output>(matching pattern: Regex<Output>) -> Output? {
    guard let next, let match = try? pattern.wholeMatch(in: next) else { return nil }
    advance()
    return match.output
  }

  /// Reads tokens up to, not including, the next comma or the end.
  mutating func skipToEndOfThird() {
    while let next, next != "," { advance() }
  }
}
