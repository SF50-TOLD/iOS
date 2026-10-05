import Foundation
import NOTAMParsing
import Testing

@testable import NOTAMModel

struct `Formatted reports as extractions` {

  private static var formattedExamples: [WorkedExample] {
    WorkedExample.all.filter(\.isFormattedReport)
  }

  private static func extraction(of example: WorkedExample) -> NOTAMExtraction? {
    FormattedReportParser().parse(notamText: example.notamText).map(NOTAMExtraction.init)
  }

  @Test(arguments: formattedExamples)
  func `reads each formatted worked example exactly as labelled`(_ example: WorkedExample) throws {
    let extraction = try #require(Self.extraction(of: example))
    #expect(extraction.canonicalized == example.gold.canonicalized)
  }

  @Test(arguments: WorkedExample.all)
  func `never reads a worked example differently from its label`(_ example: WorkedExample) {
    guard let extraction = Self.extraction(of: example) else { return }
    #expect(extraction.canonicalized == example.gold.canonicalized)
  }
}

/// A SCHEMA.md worked example: the NOTAM text and its gold reading.
struct WorkedExample: Sendable, CustomTestStringConvertible {
  /// The worked examples, shared with the evaluation target.
  static let all: [Self] = {
    let url = URL(filePath: #filePath)
      .appending(path: "../../../../NOTAMExtractionEvaluation/Data/notam_smoke.jsonl")
      .standardized
    guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return [] }
    return contents.split(separator: "\n").compactMap { try? Self(jsonLine: $0) }
  }()

  let prompt: String, gold: NOTAMExtraction

  var notamText: String { String(prompt.split(separator: "\n\n", maxSplits: 1).last ?? "") }
  var isFormattedReport: Bool {
    notamText.contains(/SNOWTAM|\bRSC \d|\bRWY \S+ FICON|\bOBST [\s\S]+FT AGL\)/)
      && !notamText.contains(/NOTAMC|CANCELED/)
  }
  var testDescription: String { String(prompt.prefix(40)) }

  init(jsonLine: Substring) throws {
    let sample = try JSONDecoder().decode(Sample.self, from: Data(jsonLine.utf8))
    prompt = sample.input.prompt
    gold = sample.output.value
  }

  private struct Sample: Decodable {
    let input: Input, output: Output

    struct Input: Decodable { let prompt: String }
    struct Output: Decodable { let value: NOTAMExtraction }
  }
}
