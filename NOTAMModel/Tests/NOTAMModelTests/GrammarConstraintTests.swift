import Foundation
import Testing

@testable import NOTAMModel

struct `Grammar constraint` {
  /// A toy vocabulary: single characters plus a few multi-character tokens, like a BPE vocabulary.
  private static let vocabulary: [String] = [
    "<eos>", "R", "W", "Y", " ", "0", "1", "2", "3", "9", "RWY", " RWY", "RWY 0", " CLSD", " PART",
    "CNL", "NIL", "\n", "ft", "m", " LEN", " DTHR", "27", "L", "/", "x", " SFC", " -", "wet", "@",
    "%"
  ]
  private static let endOfSequence = 0

  private static func constraint() -> GrammarConstraint {
    GrammarConstraint(
      pattern: ReadingGrammar.pattern,
      vocabulary: vocabulary.enumerated().map {
        $0.offset == endOfSequence ? [] : Array($0.element.utf8)
      },
      endOfSequence: endOfSequence
    )
  }

  private static func tokens(_ text: String...) -> [Int] {
    text.map { token in vocabulary.firstIndex(of: token)! }
  }

  @Test
  func `allows only tokens that can start a reading`() {
    let constraint = Self.constraint()
    let allowed = Set(constraint.allowedTokens(in: constraint.start).map { Self.vocabulary[$0] })
    #expect(allowed == ["R", "RWY", "RWY 0", "CNL", "NIL"])
  }

  @Test
  func `follows a reading token by token and allows the end only where it's whole`() throws {
    let constraint = Self.constraint()
    var state = constraint.start
    for token in Self.tokens("RWY", " ", "27", "L", " DTHR", " ", "3", "0", "0") {
      #expect(constraint.allowedTokens(in: state).contains(token))
      state = try #require(constraint.advance(state, by: token))
    }
    #expect(!constraint.allowedTokens(in: state).contains(Self.endOfSequence))
    state = try #require(constraint.advance(state, by: Self.tokens("ft")[0]))
    #expect(constraint.allowedTokens(in: state).contains(Self.endOfSequence))
  }

  @Test
  func `rejects designators, codes and units outside the schema`() throws {
    let constraint = Self.constraint()
    let afterRunway = try #require(constraint.advance(constraint.start, by: Self.tokens("RWY")[0]))
      .flatMap { constraint.advance($0, by: Self.tokens(" ")[0]) }
    let state = try #require(afterRunway)
    let allowed = Set(constraint.allowedTokens(in: state).map { Self.vocabulary[$0] })
    #expect(allowed.isSuperset(of: ["0", "1", "2", "3", "27"]))
    #expect(!allowed.contains("9"))
    #expect(!allowed.contains("x"))
  }

  @Test
  func `accepts every worked example the reading format encodes`() throws {
    let automaton = ByteAutomaton(ReadingGrammar.pattern)
    let url = URL(filePath: #filePath).appending(path: "../Fixtures/reading_format.jsonl")
      .standardized
    let lines = try String(contentsOf: url, encoding: .utf8).split(separator: "\n")
    #expect(!lines.isEmpty)
    for line in lines {
      let text =
        try #require(
          JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
        )["text"] as? String
      let state = automaton.step(automaton.start, Array(try #require(text).utf8))
      #expect(state.map(automaton.isAccepting) == true, "\(text ?? "")")
    }
  }
}
