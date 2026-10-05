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
        declaredDistances: .init(TORA: .init(value: 6787, unit: .ft), LDA: nil)
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
      NOTAMExtractor.Reading(extraction: .init(isCanceled: true, effects: []), source: .parser)
    }
    #expect(Self.value(NOTAMEvaluator.cancellationSafety, in: metrics) == .failing)
    #expect(Self.value(NOTAMEvaluator.cancellationRecall, in: metrics) == .ignore)
  }

  @Test
  func `a field neither side states is left out of safety`() async throws {
    let metrics = try await Self.metrics { _ throws(NOTAMExtractor.Failure) in
      NOTAMExtractor.Reading(extraction: Self.declaredTORA, source: .parser)
    }
    let lda = try Self.facet("LDA")
    #expect(Self.value(NOTAMEvaluator.safety(lda), in: metrics) == .ignore)
    #expect(Self.value(NOTAMEvaluator.readable, in: metrics) == .passing)
  }

  @Test
  func `reads the fields under evaluation from a comma-separated list`() {
    #expect(NOTAMExtractionEvaluation.proposableFields(from: "TORA, LDA") == [.TORA, .LDA])
    #expect(NOTAMExtractionEvaluation.proposableFields(from: nil) == Set(ProposableField.allCases))
  }

  @Test
  func `refuses a field list naming a field that doesn’t exist`() {
    #expect(NOTAMExtractionEvaluation.proposableFields(from: "TORA,LAD") == nil)
  }

  @Test
  func `limits a model reading to the fields under evaluation`() async throws {
    let evaluation = NOTAMExtractionEvaluation(dataset: .smoke, proposableFields: [.LDA]) {
      _ throws(NOTAMExtractor.Failure) in
      NOTAMExtractor.Reading(extraction: Self.declaredTORA, source: .model(version: "test"))
    }
    let subject = try await evaluation.subject(from: Self.sample)
    #expect(subject.reading.proposableFields == [.LDA])
  }

  @Test
  func `leaves a NOTAM only the model reads out of a parsers-only run`() async throws {
    let evaluation = NOTAMExtractionEvaluation(dataset: .smoke, readsWithParsersOnly: true) {
      _ throws(NOTAMExtractor.Failure) in
      throw .modelUnavailable
    }
    let subject = try await evaluation.subject(from: Self.sample)
    #expect(subject.isOutOfScope)
    #expect(subject.value.effects.isEmpty)
  }

  @Test
  func `scores a reading that flatters a declared distance as a hazard`() async throws {
    var flattering = Self.declaredTORA
    flattering.effects[0].declaredDistances?.TORA = .init(value: 7000, unit: .ft)
    let metrics = try await Self.metrics { [flattering] _ throws(NOTAMExtractor.Failure) in
      NOTAMExtractor.Reading(extraction: flattering, source: .parser)
    }
    #expect(Self.value(NOTAMEvaluator.hazardFree, in: metrics) == .failing)
    #expect(Self.value(NOTAMEvaluator.exactFill, in: metrics) == .failing)
    #expect(Self.value(NOTAMEvaluator.staysSilent, in: metrics) == .ignore)
  }

  @Test
  func `leaves a parsers-only run’s out-of-scope NOTAM out of readability and exactness`()
    async throws
  {
    let evaluation = NOTAMExtractionEvaluation(dataset: .smoke, readsWithParsersOnly: true) {
      _ throws(NOTAMExtractor.Failure) in
      throw .modelUnavailable
    }
    let reading = try await evaluation.subject(from: Self.sample)
    let metrics = try await NOTAMEvaluator().metrics(subject: reading, input: Self.sample)
    #expect(Self.value(NOTAMEvaluator.readable, in: metrics) == .ignore)
    #expect(Self.value(NOTAMEvaluator.exactFill, in: metrics) == .ignore)
    #expect(Self.value(NOTAMEvaluator.hazardFree, in: metrics) == .passing)
  }
}
