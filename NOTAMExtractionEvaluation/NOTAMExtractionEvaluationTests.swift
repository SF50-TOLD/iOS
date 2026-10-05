import Evaluations
import Foundation
import NOTAMModel
import TabularData
import Testing

@testable import SF50_Shared

@Suite(
  .enabled(
    if: NOTAMExtractionEvaluation.isConfigured,
    "set NOTAM_MODEL_FOLDER to a model folder, or NOTAM_READER to parsers, system or pcc (TEST_RUNNER_… for xcodebuild)"
  )
)
struct NOTAMExtractionEvaluationTests {
  private static let resultsDirectory = URL(filePath: #filePath).deletingLastPathComponent()
    .appending(path: "Results")
  private static let developmentReadability = 0.95, percent = 100.0

  /// The `source` of the held-out NOTAMs drawn from Zenodo record 17208970, mostly 2018 ICAO NOTAMs.
  private static let zenodoSource = "zenodo-17208970"

  private static var runInfo: [String: String] {
    [
      "variant": variant,
      "schema": NOTAMExtraction.schemaVersion,
      "proposableFields": proposableFieldsDescription
    ]
  }

  private static var includesReadability: Bool { !NOTAMExtractionEvaluation.readsWithParsersOnly }

  private static var variant: String {
    if let reader = NOTAMExtractionEvaluation.namedReader {
      return reader.stockReader?.modelVersion ?? reader.rawValue
    }
    return NOTAMExtractionEvaluation.modelFolder?.lastPathComponent ?? "unknown"
  }

  private static var proposableFieldsDescription: String {
    let list = ProcessInfo.processInfo.environment["NOTAM_PROPOSABLE_FIELDS"]
    guard let fields = NOTAMExtractionEvaluation.proposableFields(from: list) else {
      return "invalid"
    }
    return fields.map(\.rawValue).sorted().joined(separator: ",")
  }

  /// The date, model variant and dataset that begin each results file's name.
  private static func reportStem(_ name: String) -> String {
    let stamp = Date.now.formatted(.iso8601.year().month().day())
    let variant = Self.variant.replacing(" ", with: "-")
    return "\(stamp)-\(variant)-\(name)"
  }

  private static func report(_ result: EvaluationResult, name: String) throws {
    let failures = result.errors.inferenceFailureCount
    try #require(
      failures == 0,
      "\(failures) NOTAMs failed in the model or the app rather than the NOTAM, so the run measures nothing"
    )
    try FileManager.default.createDirectory(at: resultsDirectory, withIntermediateDirectories: true)
    try result.summary.writeCSV(
      to: resultsDirectory.appending(path: "\(reportStem(name))-summary.csv")
    )
    try result.detailed.writeCSV(
      to: resultsDirectory.appending(path: "\(reportStem(name))-detailed.csv")
    )
    print(result.groupedSummary)
    printGate(result)
  }

  private static func printGate(_ scores: some ExtractionScores) {
    for bar in AutoFillGate.bars(scores, includesReadability: includesReadability) {
      print("\(bar.clears ? "PASS" : "fail")  \(bar.name)  \(bar.valueDescription)")
    }
    if let hazardFree = scores.mean(of: NOTAMEvaluator.hazardFree) {
      print("hazardous per 100 NOTAMs: \((1 - hazardFree) * percent)")
    }
    for facet in ExtractionFacet.all {
      let recall = scores.mean(of: NOTAMEvaluator.recall(facet)).map { "\($0)" } ?? "n/a",
        safety = scores.mean(of: NOTAMEvaluator.safety(facet)).map { "\($0)" } ?? "n/a"
      print("      \(facet.name)  recall \(recall)  safety \(safety)")
    }
  }

  /// Reports the held-out NOTAMs from each source, and those with reviewed and unreviewed labels,
  /// apart, aggregate only.
  private static func reportHoldoutSlices(_ result: EvaluationResult) throws {
    typealias Provenance = NOTAMExtractionEvaluation.Dataset.Provenance
    let provenances = try NOTAMExtractionEvaluation.Dataset.holdout.provenances(),
      evaluation = NOTAMExtractionEvaluation(dataset: .holdout)
    let slices: [(name: String, includes: (Provenance) -> Bool)] = [
      (zenodoSource, { $0.source == zenodoSource }), ("notam-api", { $0.source != zenodoSource }),
      ("reviewed", \.isReviewed), ("unreviewed", { !$0.isReviewed })
    ]
    for slice in slices {
      let scores = SliceScores(result, of: evaluation) { sample in
        provenances[sample.promptDescription].map(slice.includes) ?? false
      }
      try scores.summary.writeCSV(
        to: resultsDirectory.appending(path: "\(reportStem("holdout"))-\(slice.name)-summary.csv")
      )
      print("\(slice.name): \(scores.count) NOTAMs")
      printGate(scores)
    }
  }

  private static func expectGateCleared(_ result: EvaluationResult) {
    for bar in AutoFillGate.bars(result, includesReadability: includesReadability) {
      #expect(bar.clears, "\(bar.name) doesn’t clear the gate: \(bar.valueDescription)")
    }
  }

  /// Whether at least `bar` of the run's NOTAMs were readable; a parsers-only run isn't measured.
  private static func readability(of result: EvaluationResult, atLeast bar: Double) -> Bool {
    !includesReadability || (result.mean(of: NOTAMEvaluator.readable) ?? 0) >= bar
  }

  @Test(.evaluates(NOTAMExtractionEvaluation(dataset: .smoke), info: runInfo))
  func `smoke: SCHEMA.md worked examples`() throws {
    let result = EvaluationContext.current.result
    try Self.report(result, name: "smoke")
    #expect(Self.readability(of: result, atLeast: 1))
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
    #expect(Self.readability(of: result, atLeast: Self.developmentReadability))
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
    Self.expectGateCleared(result)
  }

  @Test(
    .enabled(
      if: NOTAMExtractionEvaluation.Dataset.holdout.url != nil,
      "run Scripts/sync-notam-gold.sh --with-holdout"
    ),
    .evaluates(NOTAMExtractionEvaluation(dataset: .holdout), info: runInfo)
  )
  func `gate: held-out set`() throws {
    let result = EvaluationContext.current.result
    try Self.report(result, name: "holdout")
    try Self.reportHoldoutSlices(result)
    Self.expectGateCleared(result)
  }

  @Test(
    .enabled(
      if: NOTAMExtractionEvaluation.modelFolder != nil
        && !NOTAMExtractionEvaluation.readsWithParsersOnly,
      "needs the model"
    )
  )
  func `the on-device model reports a NOTAM too long to read as too long`() async throws {
    let flood = String(repeating: "RWY 09R/27L CLSD. ", count: 4000)
    let reading = try await NOTAMExtractionEvaluation(dataset: .smoke)
      .subject(from: NOTAMSample(prompt: "Location: KDTW\n\n\(flood)", expected: nil))
    #expect(reading.unreadable == .tooLong)
    #expect(reading.value.effects.isEmpty)
  }
}
