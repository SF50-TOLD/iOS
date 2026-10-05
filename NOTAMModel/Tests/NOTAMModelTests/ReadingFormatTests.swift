import Foundation
import Testing

@testable import NOTAMModel

struct `Reading format` {
  /// Every SCHEMA.md worked example in the format as Model Training's `reading_format.py` writes it,
  /// with its canonical extraction.
  private static let examples: [Example] = {
    let url = URL(filePath: #filePath).appending(path: "../Fixtures/reading_format.jsonl")
      .standardized
    guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return [] }
    return contents.split(separator: "\n").compactMap {
      try? JSONDecoder().decode(Example.self, from: Data($0.utf8))
    }
  }()

  @Test(arguments: examples)
  func `reads what Model Training writes as the extraction it encodes`(_ example: Example) throws {
    #expect(try ReadingFormat.decode(example.text).canonicalized == example.extraction)
  }

  @Test(arguments: [
    "RWY",
    "RWY 09 PART END",
    "RWY 09 CLSD FULL",
    "RWY 09 DTHR 300yd",
    "RWY 09 DTHR 0ft",
    "RWY 09 SFC CC 7/5/5 -",
    "RWY 09 TORA",
    "RWY 09 SFC slippery",
    "RWY 09 SFC wet%140",
    "OBST DIST 1nm",
    "OBST DIST 1nm DER",
    "OBST DIR 360",
    "CNL\nRWY 09 CLSD"
  ])
  func `rejects text outside the format`(_ text: String) {
    #expect(throws: ReadingFormat.Malformed.self) { try ReadingFormat.decode(text) }
  }

  struct Example: Decodable, Sendable, CustomTestStringConvertible {
    let text: String, extraction: NOTAMExtraction

    var testDescription: String { String(text.prefix(40)) }
  }
}
