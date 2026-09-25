import Evaluations
import Foundation
import NOTAMModel
import NOTAMModelRuntime

@testable import SF50_Shared

typealias NOTAMSample = ModelSample<NOTAMExtraction>

/// One reading of a NOTAM, as the evaluation scores it.
struct NOTAMReading: EvaluationSubject, Sendable {
  /// What the extractor proposed; an extraction proposing nothing when it couldn't read the NOTAM.
  let value: NOTAMExtraction
  /// Why the extractor couldn't read the NOTAM, or `nil` when it did.
  let unreadable: NOTAMExtractor.Reason?
}

/// Measures the on-device extractor against reviewed NOTAM labels, field by field.
///
/// Each field yields two metrics per NOTAM:
/// - **recall**, where the label states the field: the extraction states exactly what the label does;
/// - **safety**, where the label or the extraction states the field: the extraction shows no value
///   the NOTAM doesn't support.
///
/// A NOTAM the model can't read scores as an extraction proposing nothing — which is what the app shows
/// the pilot — and counts against ``NOTAMEvaluator/readable``. A failure of the model or the app rather
/// than the NOTAM stops the run, so it can never pass for a safe reading.
struct NOTAMExtractionEvaluation: Evaluation {
  /// Reads one NOTAM from its prompt text, `Location: <location>`, a blank line, then the NOTAM.
  typealias Extract = @Sendable (String) async throws(NOTAMExtractor.Failure) -> NOTAMExtraction

  private static let proposingNothing = NOTAMExtraction(isCanceled: false, effects: [])
  private static let locationPrefix = "Location: "

  /// The model folder under evaluation, from the `NOTAM_MODEL_FOLDER` environment variable.
  static var modelFolder: URL? {
    ProcessInfo.processInfo.environment["NOTAM_MODEL_FOLDER"].map { URL(filePath: $0) }
  }

  /// The on-device model, loaded once for the whole run.
  private static let reader = Task<NOTAMModelReader?, Never> {
    guard let modelFolder else { return nil }
    return try? await NOTAMModelReader(folder: modelFolder)
  }

  let datasetName: Dataset
  private let extract: Extract

  var dataset: JSONLoader<NOTAMSample> {
    guard let url = datasetName.url else {
      preconditionFailure(
        "\(datasetName.rawValue).jsonl isn’t bundled; run Scripts/sync-notam-gold.sh"
      )
    }
    return JSONLoader(url: url)
  }

  @EvaluatorsBuilder<NOTAMSample, NOTAMReading> var evaluators:
    [any EvaluatorProtocol<NOTAMSample, NOTAMReading>]
  {
    NOTAMEvaluator()
  }

  init(dataset: Dataset, extract: @escaping Extract = Self.onDeviceExtraction) {
    datasetName = dataset
    self.extract = extract
  }

  private static func onDeviceExtraction(_ prompt: String) async throws(NOTAMExtractor.Failure)
    -> NOTAMExtraction
  {
    guard prompt.hasPrefix(locationPrefix), let blankLine = prompt.range(of: "\n\n") else {
      preconditionFailure(
        "A gold prompt isn’t “\(locationPrefix)<location>”, a blank line, then the NOTAM"
      )
    }
    return try await NOTAMExtractor(reader: await reader.value).extract(
      notamText: String(prompt[blankLine.upperBound...]),
      location: String(prompt[..<blankLine.lowerBound].dropFirst(locationPrefix.count))
    )
  }

  func subject(from sample: NOTAMSample) async throws -> NOTAMReading {
    do {
      return NOTAMReading(value: try await extract(sample.promptDescription), unreadable: nil)
    } catch .unreadable(let reason) where reason.concernsThisNOTAM {
      return NOTAMReading(value: Self.proposingNothing, unreadable: reason)
    }
  }

  func aggregateMetrics(using aggregator: inout MetricsAggregator) {
    for metric in NOTAMEvaluator.notamMetrics { aggregator.computeMean(of: metric) }
    aggregator.group("Recall") { group in
      for facet in ExtractionFacet.all { group.computeMean(of: NOTAMEvaluator.recall(facet)) }
    }
    aggregator.group("Safety") { group in
      for facet in ExtractionFacet.all {
        let metric = NOTAMEvaluator.safety(facet)
        group.computeMean(of: metric)
        group.custom(of: metric, label: NOTAMEvaluator.failureBoundLabel(facet)) { scores in
          FailureRateBound.wilsonUpper95(scores: scores)
        }
      }
    }
  }

  enum Dataset: String, Sendable {
    case smoke = "notam_smoke", development = "notam_dev", test = "notam_test"

    /// Where the dataset is bundled, or `nil` until `Scripts/sync-notam-gold.sh` has copied it in.
    var url: URL? {
      Bundle(for: BundleToken.self).url(forResource: rawValue, withExtension: "jsonl")
    }
  }
}

/// Scores one reading of one NOTAM: whether it was read, its cancellation, whether it proposed nothing
/// where it should, and every ``ExtractionFacet``.
struct NOTAMEvaluator: EvaluatorProtocol {
  static let readable = Metric("readable"),
    cancellationRecall = Metric("isCanceled recall"),
    cancellationSafety = Metric("isCanceled safety"),
    proposesNothing = Metric("proposesNothing")

  /// The metrics scored once per NOTAM rather than per field.
  static let notamMetrics = [readable, cancellationRecall, cancellationSafety, proposesNothing]

  static func recall(_ facet: ExtractionFacet) -> Metric { Metric("\(facet.name) recall") }
  static func safety(_ facet: ExtractionFacet) -> Metric { Metric("\(facet.name) safety") }
  static func failureBoundLabel(_ facet: ExtractionFacet) -> String {
    "\(facet.name) failure upper 95%"
  }

  private static func readability(_ reading: NOTAMReading) -> Metric {
    reading.unreadable.map { readable.failing(rationale: "\($0)") } ?? readable.passing()
  }

  /// A cancellation the model misses is scored by the effects it proposes; one it invents is a
  /// safety failure, since the app would set the NOTAM aside.
  private static func cancellation(expected: NOTAMExtraction, actual: NOTAMExtraction) -> [Metric] {
    guard expected.isCanceled else {
      return [
        cancellationRecall.ignore(),
        actual.isCanceled ? cancellationSafety.failing() : cancellationSafety.passing()
      ]
    }
    return [
      actual.isCanceled ? cancellationRecall.passing() : cancellationRecall.failing(),
      cancellationSafety.ignore()
    ]
  }

  private static func proposal(expected: NOTAMExtraction, actual: NOTAMExtraction) -> Metric {
    guard expected.effects.isEmpty else { return proposesNothing.ignore() }
    return actual.effects.isEmpty
      ? proposesNothing.passing()
      : proposesNothing.failing(rationale: "proposed \(actual.effects.count) effects")
  }

  private static func metrics(_ facet: ExtractionFacet, _ score: FacetScore) -> [Metric] {
    let rationale = score.rationale.isEmpty ? nil : score.rationale
    return [
      score.readsExpected.map {
        $0 ? recall(facet).passing() : recall(facet).failing(rationale: rationale)
      } ?? recall(facet).ignore(),
      score.isSafe.map {
        $0 ? safety(facet).passing() : safety(facet).failing(rationale: rationale)
      } ?? safety(facet).ignore()
    ]
  }

  // swiftlint:disable:next async_without_await
  func metrics(subject: NOTAMReading, input: NOTAMSample) async throws -> [Metric] {
    guard let expected = input.expected else { return [] }
    let actual = subject.value
    return [Self.readability(subject), Self.proposal(expected: expected, actual: actual)]
      + Self.cancellation(expected: expected, actual: actual)
      + ExtractionFacet.all.flatMap { facet in
        Self.metrics(facet, facet.score(expected: expected, actual: actual))
      }
  }
}

private final class BundleToken {}
