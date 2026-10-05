import Foundation
import Testing

// swift-format keeps an import's attributes on its line.
// swiftlint:disable:next attributes
@_spi(NOTAMModelRuntime) @testable import NOTAMModel

struct `Reading grounding` {

  @Test(arguments: WorkedExample.all)
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
  func `refuses a compass direction the NOTAM doesn't write`() {
    let reading = NOTAMExtraction(
      isCanceled: false,
      effects: [],
      obstacles: [
        .init(
          height: .init(value: 65, unit: .ft, datum: .AGL),
          distance: nil,
          reference: nil,
          direction: .compass(.NE)
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
              .init(type: .slush, coveragePercent: 50, depth: .init(value: 1.5, unit: .in))
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
          closure: .none,
          partialClosure: .init(length: .init(value: 100, unit: .m), end: "thresholdEnd")
        )
      ]
    )
    #expect(!ReadingGrounding.isGrounded(reading, in: "RWY 26 LAST 100M CLSD DUE TO HOLE"))
  }
}
