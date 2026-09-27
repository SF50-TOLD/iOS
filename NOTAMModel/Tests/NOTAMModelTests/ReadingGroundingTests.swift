import Foundation
import Testing

// swift-format keeps an import's attributes on its line.
// swiftlint:disable:next attributes
@_spi(NOTAMModelRuntime) @testable import NOTAMModel

struct `Reading grounding` {
  private static let workedExamples: [WorkedExample] = {
    let url = URL(filePath: #filePath)
      .appending(path: "../../../../NOTAMExtractionEvaluation/Data/notam_smoke.jsonl")
      .standardized
    guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return [] }
    return contents.split(separator: "\n").compactMap { try? WorkedExample(jsonLine: $0) }
  }()

  @Test(arguments: workedExamples)
  func `accepts every worked example's label as stated by its NOTAM`(_ example: WorkedExample) {
    #expect(ReadingGrounding.isGrounded(example.gold, in: example.notamText))
  }

  @Test
  func `refuses a length the NOTAM doesn't state`() {
    let reading = NOTAMExtraction(
      isCanceled: false,
      effects: [
        .init(runway: "08", closure: .none, thresholdDisplacement: .init(value: 250, unit: .m))
      ]
    )
    #expect(
      !ReadingGrounding.isGrounded(reading, in: "RWY 08 AND RWY 26 THR DISPLACED. TORA 799M.")
    )
  }

  @Test
  func `refuses a position that isn't one the NOTAM writes`() {
    let reading = NOTAMExtraction(
      isCanceled: false,
      effects: [
        .init(
          runway: nil,
          closure: .none,
          obstacle: .init(
            heightAGL: .init(value: 65, unit: .ft),
            latitude: 52.6075,
            longitude: 0.488333
          )
        )
      ]
    )
    #expect(!ReadingGrounding.isGrounded(reading, in: "CRANE OPR PSN 523627N 0002918W 65FT AGL"))
  }

  @Test
  func `reads a fractional depth as the number it states`() {
    let reading = NOTAMExtraction(
      isCanceled: false,
      effects: [
        .init(
          runway: "16",
          closure: .none,
          surfaceCondition: .init(
            rwyCC: nil,
            contaminants: [
              .init(
                type: .slush,
                runwayThird: nil,
                coveragePercent: 50,
                depth: .init(value: 1.5, unit: .in)
              )
            ]
          )
        )
      ]
    )
    #expect(ReadingGrounding.isGrounded(reading, in: "RWY 16 FICON 50 PCT 1 1/2IN SLUSH"))
  }

  @Test
  func `refuses a closed end the NOTAM doesn't name`() {
    let reading = NOTAMExtraction(
      isCanceled: false,
      effects: [
        .init(
          runway: "26",
          closure: .partial,
          closedLength: .init(value: 100, unit: .m),
          closedEnd: "thresholdEnd"
        )
      ]
    )
    #expect(!ReadingGrounding.isGrounded(reading, in: "RWY 26 LAST 100M CLSD DUE TO HOLE"))
  }
}
