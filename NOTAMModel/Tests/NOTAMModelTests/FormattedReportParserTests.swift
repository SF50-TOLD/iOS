import Foundation
import Testing

@testable import NOTAMModel

struct `Formatted report parser` {
  /// The SCHEMA.md worked examples, with their gold readings, shared with the evaluation target.
  private static let workedExamples: [WorkedExample] = {
    let url = URL(filePath: #filePath)
      .appending(path: "../../../../NOTAMExtractionEvaluation/Data/notam_smoke.jsonl")
      .standardized
    guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return [] }
    return contents.split(separator: "\n").compactMap { try? WorkedExample(jsonLine: $0) }
  }()

  private static var formattedExamples: [WorkedExample] {
    workedExamples.filter(\.isFormattedReport)
  }

  @Test(arguments: formattedExamples)
  func `reads each formatted worked example exactly as labelled`(_ example: WorkedExample) throws {
    let reading = try #require(FormattedReportParser.parse(notamText: example.notamText))
    #expect(reading.canonicalized == example.gold.canonicalized)
  }

  @Test(arguments: workedExamples)
  func `never reads a worked example differently from its label`(_ example: WorkedExample) {
    guard let reading = FormattedReportParser.parse(notamText: example.notamText) else { return }
    #expect(reading.canonicalized == example.gold.canonicalized)
  }

  @Test
  func `reads a taxiway or apron FICON as no effects`() throws {
    let reading = try #require(
      FormattedReportParser.parse(notamText: "FNT APRON ALL FICON PATCHY ICE OBS AT 2511280114.")
    )
    #expect(reading.effects.isEmpty)
  }

  @Test(arguments: [
    // A cancellation is left to a full reading.
    "ROA RWY 06 FICON 5/5/5 100 PCT WET OBS AT 2511260325.\nCANCELED",
    // A word outside the contaminant grammar.
    "RWY 16 FICON 5/5/5 SLIPPERY WHEN WET OBS AT 2511260325.",
    // Two lists for three thirds.
    "RWY 16 FICON 5/5/5 100 PCT WET, 100 PCT WET OBS AT 2511260325.",
    // A remark that closes the runway.
    "RSC 16/34 DRY. CLOSED BY N.O.T.A.M. VALID NOV 26 1253 - NOV 26 2053.",
    // A remark that reports a contaminant the list doesn't.
    "RSC 16/34 DRY. SOME SPORATIC SMALL ICE PATCHES. VALID NOV 26 1253 - NOV 26 2053.",
    // A non-GRF remark that states a closure.
    "RSC 16/34 DRY. VALID NOV 26 1253 - NOV 26 2053.\n\nRMK: RWY 16/34 CLSD 2200-0600.",
    // Two different reports for one runway.
    "RSC 07/25 DRY. RSC 07/25 100 PCT ICE. VALID AUG 31 1208 - SEP 01 1208.",
    // A SNOWTAM remark that states a closure.
    "SWBG0510 BGSS 09141722 (SNOWTAM 0510 BGSS 09141722 13 6/6/6 NR/NR/NR NR/NR/NR DRY/DRY/DRY REMARK/ RWY 13 CLSD.)"
  ])
  func `declines a report it can't read whole`(_ notamText: String) {
    #expect(FormattedReportParser.parse(notamText: notamText) == nil)
  }

  @Test
  func `states a report repeated word for word once`() throws {
    let reading = try #require(
      FormattedReportParser.parse(
        notamText: "RSC 07/25 DRY. RSC 07/25 DRY. VALID AUG 31 1208 - SEP 01 1208."
      )
    )
    #expect(reading.effects.map(\.runway) == ["07/25"])
  }

  @Test
  func `reads each third of a RSC separately, with DRY thirds empty`() throws {
    let reading = try #require(
      FormattedReportParser.parse(
        notamText: "RSC 17L 6/6/6 10 PCT WET, DRY, DRY. VALID SEP 08 1450 - SEP 08 2250."
      )
    )
    let condition = try #require(reading.effects.first?.surfaceCondition)
    #expect(condition.rwyCC == [6, 6, 6])
    #expect(
      condition.contaminants == [.init(type: .wet, runwayThird: 1, coveragePercent: 10, depth: nil)]
    )
  }
}

/// A SCHEMA.md worked example: the NOTAM text and its gold reading.
struct WorkedExample: Sendable, CustomTestStringConvertible {
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
