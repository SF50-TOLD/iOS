import Evaluations

/// The per-field adoption bar, set before any measurement.
///
/// A field ships only if its safety and recall both clear its bar on the held-out test set. Distance fields
/// also require zero safety failures: a silently wrong distance is worse than a blank.
enum ExtractionGate {
  private static let distanceSafety = 0.995, distanceRecall = 0.70,
    categoricalSafety = 0.98, categoricalRecall = 0.80,
    cancellation = 0.98, negatives = 0.95, readability = 0.95

  static func rows(_ result: EvaluationResult) -> [Row] {
    ExtractionFacet.all.map { facet in
      let recall = measured(result.aggregateValue(.mean(of: NOTAMEvaluator.recall(facet)))),
        safety = measured(result.aggregateValue(.mean(of: NOTAMEvaluator.safety(facet)))),
        bound = result.aggregateValue(.custom(label: NOTAMEvaluator.failureBoundLabel(facet)))
      return Row(
        facet: facet.name,
        recall: recall,
        safety: safety,
        failureUpperBound: bound,
        ships: clears(facet, recall: recall, safety: safety)
      )
    }
  }

  /// Cancellations are read, and none is invented.
  static func cancellationPasses(_ result: EvaluationResult) -> Bool {
    [NOTAMEvaluator.cancellationRecall, NOTAMEvaluator.cancellationSafety].allSatisfy {
      (measured(result.aggregateValue(.mean(of: $0))) ?? 0) >= cancellation
    }
  }

  static func negativesPass(_ result: EvaluationResult) -> Bool {
    (measured(result.aggregateValue(.mean(of: NOTAMEvaluator.proposesNothing))) ?? 0) >= negatives
  }

  /// Few enough NOTAMs defeat the model that its readings describe the set.
  static func readabilityPasses(_ result: EvaluationResult) -> Bool {
    result.aggregateValue(.mean(of: NOTAMEvaluator.readable)) >= readability
  }

  /// The framework reports a negative aggregate for a metric every sample ignored.
  private static func measured(_ aggregate: Double) -> Double? {
    aggregate < 0 ? nil : aggregate
  }

  private static func clears(_ facet: ExtractionFacet, recall: Double?, safety: Double?) -> Bool {
    guard let recall, let safety else { return false }
    return facet.isDistance
      ? safety >= distanceSafety && safety == 1 && recall >= distanceRecall
      : safety >= categoricalSafety && recall >= categoricalRecall
  }

  struct Row {
    let facet: String, recall: Double?, safety: Double?, failureUpperBound: Double, ships: Bool

    var recallDescription: String { recall.map { "\($0)" } ?? "n/a" }
    var safetyDescription: String { safety.map { "\($0)" } ?? "n/a" }
  }
}
