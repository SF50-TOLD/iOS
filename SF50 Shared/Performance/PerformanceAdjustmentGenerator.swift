import Foundation

/// Determines which adjustments apply for each distance target.
///
/// ``PerformanceAdjustmentGenerator`` centralizes the "which adjustments" logic that was
/// previously duplicated across every model class. The generator inspects the current
/// conditions (wind, gradient, surface, contamination) and produces an ordered list
/// of adjustment kinds for each ``DistanceTarget``.
public struct PerformanceAdjustmentGenerator: Sendable {
  public let headwind: Double
  public let tailwind: Double
  public let uphill: Double
  public let downhill: Double
  public let isTurf: Bool
  public let contamination: Contamination?

  public init(
    headwind: Double,
    tailwind: Double,
    uphill: Double,
    downhill: Double,
    isTurf: Bool,
    contamination: Contamination?
  ) {
    self.headwind = headwind
    self.tailwind = tailwind
    self.uphill = uphill
    self.downhill = downhill
    self.isTurf = isTurf
    self.contamination = contamination
  }

  /// Returns the ordered list of adjustment kinds for a target.
  public func adjustmentKinds(for target: DistanceTarget) -> [AdjustmentKind] {
    var kinds: [AdjustmentKind] = []

    // Contamination (landing only, applied first before wind/gradient)
    if let contamination, target.isLanding {
      kinds.append(.contamination(contamination))
    }

    // Wind (all targets)
    if headwind > 0 {
      kinds.append(.headwind(.init(value: headwind, unit: .knots)))
    }
    if tailwind > 0 {
      kinds.append(.tailwind(.init(value: tailwind, unit: .knots)))
    }

    // Gradient (ground run only, not total distance)
    if target.isGroundRun {
      if uphill > 0 { kinds.append(.uphillGradient(Float(uphill))) }
      if downhill > 0 { kinds.append(.downhillGradient(Float(downhill))) }
    }

    // Unpaved surface (total distance only)
    if isTurf, target.isTotalDistance {
      kinds.append(.unpavedSurface)
    }

    return kinds
  }
}
