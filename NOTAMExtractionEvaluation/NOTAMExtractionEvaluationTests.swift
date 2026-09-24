import Evaluations
import Foundation
import FoundationModels
import TabularData
import Testing

@testable import SF50_Shared

@Suite(.enabled(if: SystemLanguageModel(useCase: .general).isAvailable, "needs Apple Intelligence"))
struct NOTAMExtractionEvaluationTests {
  private static let contextBudgetTokens = 4000
  private static let resultsDirectory = URL(filePath: #filePath).deletingLastPathComponent()
    .appending(path: "Results")

  private static var runInfo: [String: String] {
    [
      "variant": SystemLanguageModel.default.variant.displayName,
      "schema": NOTAMExtraction.schemaVersion
    ]
  }

  private static func report(_ result: EvaluationResult, name: String) throws {
    let stamp = Date.now.formatted(.iso8601.year().month().day())
    let variant = runInfo["variant", default: "unknown"].replacing(" ", with: "-")
    try FileManager.default.createDirectory(at: resultsDirectory, withIntermediateDirectories: true)
    try result.summary.writeCSV(
      to: resultsDirectory.appending(path: "\(stamp)-\(variant)-\(name)-summary.csv")
    )
    try result.detailed.writeCSV(
      to: resultsDirectory.appending(path: "\(stamp)-\(variant)-\(name)-detailed.csv")
    )
    print(result.groupedSummary)
    print("readable: \(result.aggregateValue(.mean(of: NOTAMEvaluator.readable)))")
    for row in ExtractionGate.rows(result) {
      print(
        "\(row.ships ? "SHIPS" : "no   ")  \(row.facet)  recall \(row.recallDescription)  safety \(row.safetyDescription)  failure≤\(row.failureUpperBound)"
      )
    }
  }

  @Test(.evaluates(NOTAMExtractionEvaluation(dataset: .smoke), info: runInfo))
  func `smoke: SCHEMA.md worked examples`() throws {
    let result = EvaluationContext.current.result
    try Self.report(result, name: "smoke")
    #expect(result.aggregateValue(.mean(of: NOTAMEvaluator.readable)) == 1)
  }

  @Test(
    .enabled(
      if: NOTAMExtractionEvaluation.Dataset.development.url != nil,
      "run Scripts/sync-notam-gold.sh"
    ),
    .evaluates(NOTAMExtractionEvaluation(dataset: .development), info: runInfo)
  )
  func `development set, for tuning instructions`() throws {
    let result = EvaluationContext.current.result
    try Self.report(result, name: "dev")
    #expect(ExtractionGate.readabilityPasses(result))
  }

  @Test(
    .enabled(
      if: NOTAMExtractionEvaluation.Dataset.test.url != nil,
      "run Scripts/sync-notam-gold.sh"
    ),
    .evaluates(NOTAMExtractionEvaluation(dataset: .test), info: runInfo)
  )
  func `gate: held-out test set`() throws {
    let result = EvaluationContext.current.result
    try Self.report(result, name: "test")
    for row in ExtractionGate.rows(result) {
      #expect(
        row.ships,
        "\(row.facet) doesn’t clear the gate: recall \(row.recallDescription), safety \(row.safetyDescription)"
      )
    }
    #expect(ExtractionGate.cancellationPasses(result))
    #expect(ExtractionGate.negativesPass(result))
    #expect(ExtractionGate.readabilityPasses(result))
  }

  @Test
  func `instructions and schema leave room for a long NOTAM`() async throws {
    let model = SystemLanguageModel(useCase: .general)
    let tokens =
      try await model.tokenCount(for: Instructions(NOTAMExtractionInstructions.text))
      + model.tokenCount(for: NOTAMExtraction.generationSchema)
    #expect(
      tokens <= Self.contextBudgetTokens,
      "instructions + schema use \(tokens) of \(model.contextSize) tokens"
    )
  }

  @Test
  func `the on-device model reports a NOTAM too long to read as too long`() async throws {
    let flood = String(repeating: "RWY 09R/27L CLSD. ", count: 4000)
    let reading = try await NOTAMExtractionEvaluation(dataset: .smoke)
      .subject(from: NOTAMSample(prompt: "Location: KDTW\n\n\(flood)", expected: nil))
    #expect(reading.unreadable == .tooLong)
    #expect(reading.value.effects.isEmpty)
  }
}
