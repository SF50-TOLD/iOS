import Evaluations
import TabularData

/// The aggregate scores ``AutoFillGate`` reads: of a whole evaluation run, or of a slice of its NOTAMs.
protocol ExtractionScores {

  /// The one-sided 95% upper bound on the share of NOTAMs whose Auto-Fill offer is hazardous.
  var hazardUpperBound: Double { get }

  /// The mean of a metric over the NOTAMs it scored, or `nil` when it scored none.
  func mean(of metric: Metric) -> Double?

  /// The upper end of the 95% Wilson interval on a facet's safety-failure rate.
  func failureUpperBound(_ facet: ExtractionFacet) -> Double
}

extension EvaluationResult: ExtractionScores {
  var hazardUpperBound: Double { aggregateValue(.custom(label: NOTAMEvaluator.hazardBoundLabel)) }

  /// The framework reports a negative aggregate for a metric every sample ignored.
  func mean(of metric: Metric) -> Double? {
    let aggregate = aggregateValue(.mean(of: metric))
    return aggregate < 0 ? nil : aggregate
  }

  func failureUpperBound(_ facet: ExtractionFacet) -> Double {
    aggregateValue(.custom(label: NOTAMEvaluator.failureBoundLabel(facet)))
  }
}

/// The scores of some of a run's NOTAMs, aggregated from their per-NOTAM metrics.
struct SliceScores: ExtractionScores {
  /// How many NOTAMs the slice holds.
  let count: Int
  private let scores: [String: [Double]]

  var hazardUpperBound: Double {
    FailureRateBound.oneSidedUpper95(scores: scores[NOTAMEvaluator.hazardFree.name, default: []])
  }

  /// The summary of the slice: one row per aggregate the gate reads.
  var summary: DataFrame {
    let means = NOTAMEvaluator.allMetrics.map { ($0.name, mean(of: $0)) },
      bounds = ExtractionFacet.all.map {
        (NOTAMEvaluator.failureBoundLabel($0), Optional(failureUpperBound($0)))
      }
    let rows =
      [("NOTAMs", Optional(Double(count)))] + means
      + [(NOTAMEvaluator.hazardBoundLabel, Optional(hazardUpperBound))] + bounds
    return DataFrame(columns: [
      Column(name: "aggregate", contents: rows.map(\.0)).eraseToAnyColumn(),
      Column(name: "value", contents: rows.map(\.1)).eraseToAnyColumn()
    ])
  }

  /// Scores the NOTAMs of a run that `includes` admits, from their metrics.
  init(
    _ rows: some Sequence<(sample: NOTAMSample, metrics: [Metric])>,
    where includes: (NOTAMSample) -> Bool
  ) {
    let metrics = rows.filter { includes($0.sample) }.map(\.metrics)
    count = metrics.count
    scores = Dictionary(grouping: metrics.joined(), by: \.name).mapValues {
      $0.compactMap(Self.score)
    }
  }

  /// Scores the NOTAMs of an evaluation run that `includes` admits.
  init(
    _ result: EvaluationResult,
    of evaluation: NOTAMExtractionEvaluation,
    where includes: (NOTAMSample) -> Bool
  ) {
    let detailed = result.detailed, inputs = detailed[evaluation.inputColumn],
      columns = NOTAMEvaluator.allMetrics.map { detailed[metric: $0] }
    let rows = inputs.indices.compactMap { row in
      inputs[row].map { (sample: $0, metrics: columns.compactMap { $0[row] }) }
    }
    self.init(rows, where: includes)
  }

  /// A pass as 1 and a failure as 0; `nil` for a NOTAM the metric ignored.
  private static func score(_ metric: Metric) -> Double? {
    switch metric.value {
      case .passing: 1
      case .failing: 0
      case .scoring(let value): value
      case .ignore: nil
      @unknown default: nil
    }
  }

  func mean(of metric: Metric) -> Double? {
    let scores = scores[metric.name, default: []]
    return scores.isEmpty ? nil : scores.reduce(0, +) / Double(scores.count)
  }

  func failureUpperBound(_ facet: ExtractionFacet) -> Double {
    FailureRateBound.wilsonUpper95(scores: scores[NOTAMEvaluator.safety(facet).name, default: []])
  }
}
