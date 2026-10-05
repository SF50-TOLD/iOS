import Foundation

/// Bounds a measured failure rate, so a small set can't pass for a proven one.
enum FailureRateBound {
  private static let z95 = 1.959964
  private static let oneSidedAlpha = 0.05, bisectionSteps = 60

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

  /// The one-sided 95% upper bound on a failure rate: the exact (Clopper–Pearson) binomial bound,
  /// the highest rate at which so few failures would still happen 5% of the time.
  static func oneSidedUpper95(failures: Int, trials: Int) -> Double {
    guard trials > 0, failures < trials else { return 1 }
    var low = Double(failures) / Double(trials), high = 1.0
    for _ in 0..<bisectionSteps {
      let rate = (low + high) / 2
      if binomialCDF(failures: failures, trials: trials, rate: rate) > oneSidedAlpha {
        low = rate
      } else {
        high = rate
      }
    }
    return high
  }

  /// The one-sided upper bound over metric scores, counting only passes (1) and failures (0).
  static func oneSidedUpper95(scores: [Double]) -> Double {
    let trials = scores.filter { $0 == 0 || $0 == 1 }
    return oneSidedUpper95(failures: trials.count(where: { $0 == 0 }), trials: trials.count)
  }

  /// The chance of at most `failures` failures in `trials` trials at a failure rate of `rate`.
  private static func binomialCDF(failures: Int, trials: Int, rate: Double) -> Double {
    (0...failures).reduce(0) { sum, count in
      sum
        + exp(
          logChoose(trials, count) + Double(count) * log(rate)
            + Double(trials - count) * log1p(-rate)
        )
    }
  }

  private static func logChoose(_ total: Int, _ chosen: Int) -> Double {
    lgamma(Double(total + 1)) - lgamma(Double(chosen + 1)) - lgamma(Double(total - chosen + 1))
  }
}
