import Evaluations
import Foundation
import NOTAMModel
import TabularData
import Testing

@testable import SF50_Shared

@Suite(
  .enabled(
    if: NOTAMExtractionEvaluation.modelFolder != nil,
    "set NOTAM_MODEL_FOLDER (TEST_RUNNER_NOTAM_MODEL_FOLDER for xcodebuild) to a model folder"
  )
)
struct NOTAMExtractionEvaluationTests {
  private static let resultsDirectory = URL(filePath: #filePath).deletingLastPathComponent()
    .appending(path: "Results")

  private static var runInfo: [String: String] {
    [
      "variant": NOTAMExtractionEvaluation.modelFolder?.lastPathComponent ?? "unknown",
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
  func `the on-device model reports a NOTAM too long to read as too long`() async throws {
    let flood = String(repeating: "RWY 09R/27L CLSD. ", count: 4000)
    let reading = try await NOTAMExtractionEvaluation(dataset: .smoke)
      .subject(from: NOTAMSample(prompt: "Location: KDTW\n\n\(flood)", expected: nil))
    #expect(reading.unreadable == .tooLong)
    #expect(reading.value.effects.isEmpty)
  }
}
