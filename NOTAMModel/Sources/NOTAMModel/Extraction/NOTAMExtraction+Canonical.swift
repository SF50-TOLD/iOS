extension NOTAMExtraction {
  /**
   The extraction in the canonical order `SCHEMA.md` defines, so two readings of the same NOTAM are
   equal exactly when they state the same facts.

   - Effects sort by runway, the aerodrome (`nil`) first.
   - Obstacles sort by their reference's runway (`nil` first), its kind, then height, distance and
     direction.
   - Contaminants are deduplicated, then sorted by type, coverage and depth.

   Every sort is stable.
   */
  public var canonicalized: Self {
    var copy = self
    copy.effects = effects.map(\.canonicalized).stablySorted { lhs, rhs in
      Self.precedes(lhs.runway, rhs.runway)
    }
    copy.obstacles = obstacles.stablySorted { $0.sortKey.lexicographicallyPrecedes($1.sortKey) }
    return copy
  }

  /// Whether `lhs` sorts before `rhs`, `nil` first.
  fileprivate static func precedes<Value: Comparable>(_ lhs: Value?, _ rhs: Value?) -> Bool {
    switch (lhs, rhs) {
      case (nil, .some): true
      case let (left?, right?): left < right
      default: false
    }
  }
}

extension NOTAMExtraction.RunwayEffect {
  fileprivate var canonicalized: Self {
    var copy = self
    if let condition = surfaceCondition {
      let distinct = condition.contaminants.reduce(into: [NOTAMExtraction.Contaminant]()) {
        if !$0.contains($1) { $0.append($1) }
      }
      copy.surfaceCondition?.contaminants = distinct.stablySorted {
        $0.sortKey.lexicographicallyPrecedes($1.sortKey)
      }
    }
    return copy
  }
}

extension NOTAMExtraction.Contaminant {
  /// Type, coverage (`nil` first), then depth (`nil` first).
  fileprivate var sortKey: [SortField] {
    [
      .text(type.rawValue), coveragePercent.map { .number(Double($0)) } ?? .missing,
      depth.map { .number($0.value) } ?? .missing
    ]
  }
}

extension NOTAMExtraction.Obstacle {
  /// Reference runway and kind, height, distance, then direction; `nil` first throughout.
  fileprivate var sortKey: [SortField] {
    [
      reference?.runway.map(SortField.text) ?? .missing,
      reference.map { .text($0.kind.rawValue) } ?? .missing,
      height.map { .number($0.value) } ?? .missing,
      distance.map { .number($0.value) } ?? .missing,
      direction.map(\.sortField) ?? .missing
    ]
  }
}

extension NOTAMExtraction.ObstacleDirection {
  fileprivate var sortField: SortField {
    switch self {
      case .compass(let point): .text(point.rawValue)
      case .degrees(let degrees): .number(degrees)
    }
  }
}

/// One field of a sort key: a missing value sorts first, then numbers, then text.
private enum SortField: Comparable {
  case missing
  case number(Double)
  case text(String)
}

extension Array {
  /// The array sorted by `areInIncreasingOrder`, keeping the order of elements that tie.
  fileprivate func stablySorted(by areInIncreasingOrder: (Element, Element) -> Bool) -> Self {
    enumerated()
      .sorted { lhs, rhs in
        if areInIncreasingOrder(lhs.element, rhs.element) { return true }
        if areInIncreasingOrder(rhs.element, lhs.element) { return false }
        return lhs.offset < rhs.offset
      }
      .map(\.element)
  }
}
