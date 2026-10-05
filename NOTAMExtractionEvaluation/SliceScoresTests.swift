import Evaluations
import NOTAMModel
import Testing

struct `Slice scores` {
  private static let proposingNothing = NOTAMExtraction(isCanceled: false, effects: [])

  private static func sample(_ text: String) -> NOTAMSample {
    NOTAMSample(prompt: "Location: DTW\n\n\(text)", expected: proposingNothing)
  }

  @Test
  func `score only the slice’s NOTAMs, and only where a metric scored them`() throws {
    let inSlice = Self.sample("RWY 09R CLSD"), outOfSlice = Self.sample("TWY A CLSD")
    let negatives = NOTAMEvaluator.proposesNothing, readable = NOTAMEvaluator.readable
    let rows: [(sample: NOTAMSample, metrics: [Metric])] = [
      (inSlice, [negatives.failing(), readable.passing()]),
      (inSlice, [negatives.ignore(), readable.passing()]),
      (inSlice, [negatives.passing(), readable.failing()]),
      (outOfSlice, [negatives.failing(), readable.failing()])
    ]
    let scores = SliceScores(rows) { $0.promptDescription == inSlice.promptDescription }

    #expect(scores.count == 3)
    #expect(scores.mean(of: negatives) == 0.5)
    #expect(try #require(scores.mean(of: readable)) == 2.0 / 3)
    #expect(scores.mean(of: NOTAMEvaluator.cancellationRecall) == nil)
    #expect(scores.hazardUpperBound == FailureRateBound.oneSidedUpper95(scores: []))
  }
}
