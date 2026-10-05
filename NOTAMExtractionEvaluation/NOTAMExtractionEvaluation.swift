import Evaluations
import Foundation
import FoundationModels
import NOTAMModel
import NOTAMModelRuntime

@testable import SF50_Shared

typealias NOTAMSample = ModelSample<NOTAMExtraction>

/// One reading of a NOTAM, as the evaluation scores it.
struct NOTAMReading: EvaluationSubject, Sendable {
  /// What the extractor read; a reading proposing nothing when it couldn't read the NOTAM.
  let reading: NOTAMExtractor.Reading
  /// Why the extractor couldn't read the NOTAM, or `nil` when it did.
  let unreadable: NOTAMExtractor.Reason?
  /// Whether the NOTAM was outside the reader under evaluation: a parsers-only run met a NOTAM only
  /// the model reads.
  let isOutOfScope: Bool

  var value: NOTAMExtraction { reading.extraction }
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
  typealias Extract =
    @Sendable (String) async throws(NOTAMExtractor.Failure) ->
    NOTAMExtractor.Reading

  private static let
    proposingNothing = NOTAMExtractor.Reading(
      extraction: NOTAMExtraction(isCanceled: false, effects: []),
      source: .parser
    ),
    locationPrefix = "Location: ",
    fieldSeparator: Character = ","

  /// The model folder under evaluation, from the `NOTAM_MODEL_FOLDER` environment variable.
  static var modelFolder: URL? {
    ProcessInfo.processInfo.environment["NOTAM_MODEL_FOLDER"].map { URL(filePath: $0) }
  }

  /// The reader the `NOTAM_READER` environment variable names, if any.
  static var namedReader: NamedReader? {
    ProcessInfo.processInfo.environment["NOTAM_READER"].flatMap(NamedReader.init)
  }

  /// Whether the run reads with the parsers alone.
  static var readsWithParsersOnly: Bool { namedReader == .parsers }

  /// Whether the environment names a reader to evaluate.
  static var isConfigured: Bool { modelFolder != nil || namedReader != nil }

  /// The fields model readings may propose, from `NOTAM_PROPOSABLE_FIELDS`; a name that isn't a
  /// field stops the run.
  private static var fieldsUnderEvaluation: Set<ProposableField> {
    let list = ProcessInfo.processInfo.environment["NOTAM_PROPOSABLE_FIELDS"]
    guard let fields = proposableFields(from: list) else {
      preconditionFailure("NOTAM_PROPOSABLE_FIELDS names a field that doesn’t exist: \(list ?? "")")
    }
    return fields
  }

  /// The model under evaluation, loaded once for the whole run; a model that won't load stops the
  /// run.
  private static let reader = Task<(any NOTAMReader)?, Never> {
    if let stock = namedReader?.stockReader { return stock }
    guard let modelFolder, !readsWithParsersOnly else { return nil }
    do {
      return try await NOTAMModelReader(folder: modelFolder)
    } catch {
      preconditionFailure("The model in \(modelFolder.path) couldn’t be loaded: \(error)")
    }
  }

  let datasetName: Dataset
  private let extract: Extract, proposableFields: Set<ProposableField>, readsWithParsersOnly: Bool

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

  init(
    dataset: Dataset,
    proposableFields: Set<ProposableField> = Self.fieldsUnderEvaluation,
    readsWithParsersOnly: Bool = Self.readsWithParsersOnly,
    extract: @escaping Extract = Self.onDeviceExtraction
  ) {
    datasetName = dataset
    self.extract = extract
    self.proposableFields = proposableFields
    self.readsWithParsersOnly = readsWithParsersOnly
  }

  /// The fields a comma-separated list names, every field for no list, or `nil` when a name isn't a
  /// field.
  static func proposableFields(from list: String?) -> Set<ProposableField>? {
    guard let list, !list.isEmpty else { return Set(ProposableField.allCases) }
    let fields = list.split(separator: fieldSeparator).map {
      ProposableField(rawValue: $0.trimmingCharacters(in: .whitespaces))
    }
    return fields.contains(nil) ? nil : Set(fields.compactMap(\.self))
  }

  private static func onDeviceExtraction(_ prompt: String) async throws(NOTAMExtractor.Failure)
    -> NOTAMExtractor.Reading
  {
    guard prompt.hasPrefix(locationPrefix), let blankLine = prompt.range(of: "\n\n") else {
      preconditionFailure(
        "A gold prompt isn’t “\(locationPrefix)<location>”, a blank line, then the NOTAM"
      )
    }
    return try await NOTAMExtractor(
      reader: await reader.value,
      parsesFormattedReports: namedReader?.stockReader == nil
    ).read(
      notamText: String(prompt[blankLine.upperBound...]),
      location: String(prompt[..<blankLine.lowerBound].dropFirst(locationPrefix.count))
    )
  }

  func subject(from sample: NOTAMSample) async throws -> NOTAMReading {
    do {
      return NOTAMReading(
        reading: underEvaluation(try await extract(sample.promptDescription)),
        unreadable: nil,
        isOutOfScope: false
      )
    } catch .unreadable(let reason) where reason.concernsThisNOTAM {
      return NOTAMReading(reading: Self.proposingNothing, unreadable: reason, isOutOfScope: false)
    } catch .modelUnavailable where readsWithParsersOnly {
      return NOTAMReading(reading: Self.proposingNothing, unreadable: nil, isOutOfScope: true)
    }
  }

  /// A model reading proposes only the fields under evaluation, whatever its manifest lists.
  private func underEvaluation(_ reading: NOTAMExtractor.Reading) -> NOTAMExtractor.Reading {
    guard case .model = reading.source else { return reading }
    return reading.limited(to: proposableFields)
  }

  func aggregateMetrics(using aggregator: inout MetricsAggregator) {
    for metric in NOTAMEvaluator.notamMetrics { aggregator.computeMean(of: metric) }
    aggregator.custom(of: NOTAMEvaluator.hazardFree, label: NOTAMEvaluator.hazardBoundLabel) {
      FailureRateBound.oneSidedUpper95(scores: $0)
    }
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

  /// A reader `NOTAM_READER` names: the parsers alone, or a stock model reading every NOTAM.
  enum NamedReader: String, Sendable {
    case parsers
    /// The on-device `SystemLanguageModel`.
    case system
    /// `PrivateCloudComputeLanguageModel`, which needs the Private Cloud Compute entitlement.
    case privateCloudCompute = "pcc"

    /// The stock model this names, or `nil` for the parsers; an unavailable model stops the run.
    var stockReader: StockModelReader? {
      switch self {
        case .parsers:
          return nil
        case .system:
          let model = SystemLanguageModel(useCase: .general)
          precondition(
            model.isAvailable,
            "The on-device model isn’t available: \(model.availability)"
          )
          return StockModelReader(model: model, name: "system-on-device")
        case .privateCloudCompute:
          let model = PrivateCloudComputeLanguageModel()
          precondition(
            model.isAvailable,
            "Private Cloud Compute isn’t available: \(model.availability)"
          )
          return StockModelReader(model: model, name: "private-cloud-compute")
      }
    }
  }

  enum Dataset: String, Sendable {
    case smoke = "notam_smoke", development = "notam_dev", test = "notam_test",
      holdout = "notam_holdout"

    /// Where the dataset is bundled, or `nil` until `Scripts/sync-notam-gold.sh` has copied it in.
    var url: URL? {
      Bundle(for: BundleToken.self).url(forResource: rawValue, withExtension: "jsonl")
    }

    /// Where the dataset's metadata is bundled, line for line with the dataset.
    private var metadataURL: URL? {
      Bundle(for: BundleToken.self).url(forResource: "\(rawValue).meta", withExtension: "jsonl")
    }

    private static func lines(_ url: URL) throws -> [Data] {
      try String(contentsOf: url, encoding: .utf8).split(whereSeparator: \.isNewline).map {
        Data($0.utf8)
      }
    }

    /// Each NOTAM's metadata, keyed by the NOTAM's prompt.
    func provenances() throws -> [String: Provenance] {
      guard let url, let metadataURL else {
        preconditionFailure(
          "\(rawValue) and its metadata aren’t bundled; run Scripts/sync-notam-gold.sh"
        )
      }
      let decoder = JSONDecoder()
      let prompts = try Self.lines(url).map {
        try decoder.decode(NOTAMSample.self, from: $0).promptDescription
      }
      let provenances = try Self.lines(metadataURL).map {
        try decoder.decode(Provenance.self, from: $0)
      }
      precondition(
        prompts.count == provenances.count,
        "\(rawValue) and its metadata differ in length"
      )
      return Dictionary(zip(prompts, provenances)) { first, _ in first }
    }

    /// Where a NOTAM's label came from.
    struct Provenance: Decodable {
      /// The marker that begins `reviewer` on a silver label nobody reviewed.
      private static let unreviewedMarker = "Unreviewed"

      /// Where the NOTAM was collected: a download date, or a dataset such as Zenodo's.
      let source: String
      /// Who reviewed the label.
      let reviewer: String?

      /// Whether a person reviewed the label.
      var isReviewed: Bool { !(reviewer ?? Self.unreviewedMarker).hasPrefix(Self.unreviewedMarker) }
    }
  }
}

/// Scores one reading of one NOTAM: whether it was read, its cancellation, whether it proposed nothing
/// where it should, and every ``ExtractionFacet``.
struct NOTAMEvaluator: EvaluatorProtocol {
  static let readable = Metric("readable"),
    cancellationRecall = Metric("isCanceled recall"),
    cancellationSafety = Metric("isCanceled safety"),
    proposesNothing = Metric("proposesNothing"),
    hazardFree = Metric("hazardFree"),
    exactFill = Metric("exactFill"),
    cautionFree = Metric("cautionFree"),
    staysSilent = Metric("staysSilent"),
    hazardBoundLabel = "hazardous upper 95% one-sided"

  /// The metrics scored once per NOTAM rather than per field.
  static let notamMetrics = [
    readable, cancellationRecall, cancellationSafety, proposesNothing,
    hazardFree, exactFill, cautionFree, staysSilent
  ]

  /// Every metric the evaluator scores.
  static var allMetrics: [Metric] {
    notamMetrics + ExtractionFacet.all.flatMap { [recall($0), safety($0)] }
  }

  static func recall(_ facet: ExtractionFacet) -> Metric { Metric("\(facet.name) recall") }
  static func safety(_ facet: ExtractionFacet) -> Metric { Metric("\(facet.name) safety") }
  static func failureBoundLabel(_ facet: ExtractionFacet) -> String {
    "\(facet.name) failure upper 95%"
  }

  private static func readability(_ reading: NOTAMReading) -> Metric {
    if reading.isOutOfScope { return readable.ignore() }
    return reading.unreadable.map { readable.failing(rationale: "\($0)") } ?? readable.passing()
  }

  /// How the Auto-Fill offer compares with the label's: every NOTAM is a hazard trial; exactness
  /// counts where the label offers something, caution where the reading does, and silence where the
  /// label offers nothing.
  private static func autoFill(_ subject: NOTAMReading, expected: NOTAMExtraction) -> [Metric] {
    let outcome = AutoFillOutcome.of(subject.reading, expected: expected),
      labelOffers = AutoFillOutcome.offersAnything(AutoFillOutcome.label(expected)),
      readingOffers = AutoFillOutcome.offersAnything(subject.reading)
    let exactness =
      outcome == .exact ? exactFill.passing() : exactFill.failing(rationale: "\(outcome)")
    let silence = readingOffers ? staysSilent.failing() : staysSilent.passing()
    return [
      outcome == .hazardous ? hazardFree.failing() : hazardFree.passing(),
      labelOffers && !subject.isOutOfScope ? exactness : exactFill.ignore(),
      readingOffers
        ? (outcome == .cautious ? cautionFree.failing() : cautionFree.passing())
        : cautionFree.ignore(),
      labelOffers ? staysSilent.ignore() : silence
    ]
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
    guard expected.effects.isEmpty, expected.obstacles.isEmpty else {
      return proposesNothing.ignore()
    }
    return actual.effects.isEmpty && actual.obstacles.isEmpty
      ? proposesNothing.passing()
      : proposesNothing.failing(
        rationale: "proposed \(actual.effects.count) effects, \(actual.obstacles.count) obstacles"
      )
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
      + Self.autoFill(subject, expected: expected)
      + ExtractionFacet.all.flatMap { facet in
        Self.metrics(facet, facet.score(expected: expected, actual: actual))
      }
  }
}

private final class BundleToken {}
