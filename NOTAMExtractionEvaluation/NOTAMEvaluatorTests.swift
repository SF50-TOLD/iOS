import Evaluations
import NOTAMModel
import Testing

@testable import SF50_Shared

struct NOTAMEvaluatorTests {
  private static let declaredTORA = NOTAMExtraction(
    isCanceled: false,
    effects: [
      .init(
        runway: "09R",
        closure: .none,
        closedLength: nil,
        closedEnd: nil,
        thresholdDisplacement: nil,
        declaredDistances: .init(
          TORA: .init(value: 6787, unit: .ft),
          TODA: nil,
          ASDA: nil,
          LDA: nil
        ),
        surfaceCondition: nil,
        obstacle: nil
      )
    ]
  )
  private static let sample = NOTAMSample(
    prompt: "Location: DTW\n\nDTW RWY 09R DECLARED DIST: TORA 6787FT",
    expected: declaredTORA
  )
  private static let failuresOfTheModel: [NOTAMExtractor.Failure] = [
    .modelUnavailable, .cancelled, .unreadable(.modelFailed)
  ]

  private static func metrics(reading extract: @escaping NOTAMExtractionEvaluation.Extract)
    async throws -> [Metric]
  {
    let evaluation = NOTAMExtractionEvaluation(dataset: .smoke, extract: extract)
    let reading = try await evaluation.subject(from: sample)
    return try await NOTAMEvaluator().metrics(subject: reading, input: sample)
  }

  private static func value(_ metric: Metric, in metrics: [Metric]) -> Metric.Value? {
    metrics[metric]?.value
  }

  private static func facet(_ name: String) throws -> ExtractionFacet {
    try #require(ExtractionFacet.all.first { $0.name == name })
  }

  @Test
  func `a NOTAM the model can't read is a counted, safe miss`() async throws {
    let metrics = try await Self.metrics { _ throws(NOTAMExtractor.Failure) in
      throw .unreadable(.tooLong)
    }
    let tora = try Self.facet("TORA")
    #expect(Self.value(NOTAMEvaluator.readable, in: metrics) == .failing)
    #expect(Self.value(NOTAMEvaluator.recall(tora), in: metrics) == .failing)
    #expect(Self.value(NOTAMEvaluator.safety(tora), in: metrics) == .passing)
  }

  @Test(arguments: failuresOfTheModel)
  func `a failure of the model rather than the NOTAM stops the run`(
    failure: NOTAMExtractor.Failure
  ) async {
    let evaluation = NOTAMExtractionEvaluation(dataset: .smoke) {
      _ throws(NOTAMExtractor.Failure) in
      throw failure
    }
    await #expect(throws: NOTAMExtractor.Failure.self) {
      try await evaluation.subject(from: Self.sample)
    }
  }

  @Test
  func `a false cancellation is a safety failure`() async throws {
    let metrics = try await Self.metrics { _ throws(NOTAMExtractor.Failure) in
      NOTAMExtraction(isCanceled: true, effects: [])
    }
    #expect(Self.value(NOTAMEvaluator.cancellationSafety, in: metrics) == .failing)
    #expect(Self.value(NOTAMEvaluator.cancellationRecall, in: metrics) == .ignore)
  }

  @Test
  func `a field neither side states is left out of safety`() async throws {
    let metrics = try await Self.metrics { _ throws(NOTAMExtractor.Failure) in Self.declaredTORA }
    let lda = try Self.facet("LDA")
    #expect(Self.value(NOTAMEvaluator.safety(lda), in: metrics) == .ignore)
    #expect(Self.value(NOTAMEvaluator.readable, in: metrics) == .passing)
  }
}
