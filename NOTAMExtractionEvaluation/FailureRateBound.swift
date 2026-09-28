import Foundation

/// Bounds a measured failure rate, so a small test set can't pass for a proven one.
enum FailureRateBound {
  private static let z95 = 1.959964

  /// The upper end of the 95% Wilson score interval for a failure rate.
  static func wilsonUpper95(failures: Int, trials: Int) -> Double {
    guard trials > 0 else { return 1 }
    let n = Double(trials), rate = Double(failures) / n, z² = z95 * z95
    let centre = rate + z² / (2 * n)
    let spread = z95 * (rate * (1 - rate) / n + z² / (4 * n * n)).squareRoot()
    return min(1, (centre + spread) / (1 + z² / n))
  }

  /// The Wilson upper bound over metric scores, counting only passes (1) and failures (0), so
  /// placeholder values for ignored samples can't count as trials or failures.
  static func wilsonUpper95(scores: [Double]) -> Double {
    let trials = scores.filter { $0 == 0 || $0 == 1 }
    return wilsonUpper95(failures: trials.count(where: { $0 == 0 }), trials: trials.count)
  }
}
