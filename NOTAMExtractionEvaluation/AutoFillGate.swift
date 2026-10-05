/// The Auto-Fill gate, as `Results/AUTO-FILL-GATE.md` sets it out.
///
/// A reader ships only if every bar clears on one run of the held-out set.
enum AutoFillGate {
  private static let hazardBound = 0.01, exact = 0.50, cautionFree = 0.90, staysSilent = 0.95,
    readability = 0.95

  /// The gate's bars, measured; readability is left out of a parsers-only run, which reads only the
  /// NOTAMs the parsers recognize.
  static func bars(_ scores: some ExtractionScores, includesReadability: Bool) -> [Bar] {
    let hazard = scores.hazardUpperBound
    let bars = [
      Bar(name: "hazardous (upper bound)", value: hazard, clears: hazard <= hazardBound),
      at(least: exact, "exact", scores.mean(of: NOTAMEvaluator.exactFill)),
      at(least: cautionFree, "not cautious", scores.mean(of: NOTAMEvaluator.cautionFree)),
      at(least: staysSilent, "stays silent", scores.mean(of: NOTAMEvaluator.staysSilent))
    ]
    guard includesReadability else { return bars }
    return bars + [at(least: readability, "readable", scores.mean(of: NOTAMEvaluator.readable))]
  }

  private static func at(least bar: Double, _ name: String, _ value: Double?) -> Bar {
    Bar(name: name, value: value, clears: (value ?? 0) >= bar)
  }

  struct Bar {
    let name: String, value: Double?, clears: Bool

    var valueDescription: String { value.map { "\($0)" } ?? "n/a" }
  }
}
