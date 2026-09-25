@testable import NOTAMModel

extension NOTAMExtraction {
  /**
   The extraction with its effects and contaminants in the canonical order `SCHEMA.md` defines.

   Effects sort by runway (the aerodrome first, then designators in lexicographic order), then closure
   (`none`, `full`, `partial`), then by whether each of threshold displacement, declared distances,
   surface condition and obstacle is present (absent first); remaining ties keep their order.
   Contaminants sort by runway third (the whole runway first) and then by type. Two readings of the
   same NOTAM are equal exactly when their canonical forms are.
   */
  var canonicalized: Self {
    var copy = self
    copy.effects = effects.enumerated()
      .sorted { ($0.element.sortKey, $0.offset) < ($1.element.sortKey, $1.offset) }
      .map(\.element.canonicalized)
    return copy
  }
}

extension NOTAMExtraction.RunwayEffect {
  /// The designator, then closure and presence ranks, compared in that order.
  fileprivate var sortKey: EffectSortKey {
    let presence = [
      thresholdDisplacement != nil, declaredDistances != nil, surfaceCondition != nil,
      obstacle != nil
    ]
    return .init(runway: runway, ranks: [closure.canonicalRank] + presence.map { $0 ? 1 : 0 })
  }

  fileprivate var canonicalized: Self {
    var copy = self
    copy.surfaceCondition?.contaminants.sort { lhs, rhs in
      (lhs.runwayThird ?? 0, lhs.type.rawValue) < (rhs.runwayThird ?? 0, rhs.type.rawValue)
    }
    return copy
  }
}

extension NOTAMExtraction.Closure {
  fileprivate var canonicalRank: Int {
    switch self {
      case .none: 0
      case .full: 1
      case .partial: 2
    }
  }
}

private struct EffectSortKey: Comparable {
  let runway: String?, ranks: [Int]

  static func < (lhs: Self, rhs: Self) -> Bool {
    switch (lhs.runway, rhs.runway) {
      case (nil, .some): return true
      case (.some, nil): return false
      case let (left?, right?) where left != right: return left < right
      default: return lhs.ranks.lexicographicallyPrecedes(rhs.ranks)
    }
  }
}
