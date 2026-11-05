public import Foundation

extension Runway {
  /// Orders runways by designator, as ``RunwayDesignator/compare(_:_:)`` defines it.
  public struct NameComparator: SortComparator {
    public var order: SortOrder = .forward

    public init(order: SortOrder = .forward) {
      self.order = order
    }

    public func compare(_ lhs: Runway, _ rhs: Runway) -> ComparisonResult {
      let result = RunwayDesignator.compare(lhs.name, rhs.name)
      return order == .forward ? result : result.inverted
    }
  }
}

extension ComparisonResult {
  fileprivate var inverted: Self {
    switch self {
      case .orderedAscending: .orderedDescending
      case .orderedDescending: .orderedAscending
      case .orderedSame: .orderedSame
    }
  }
}
