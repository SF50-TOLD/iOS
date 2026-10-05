public import Foundation

extension NOTAMResponse {
  /// How long either side of the planned time a NOTAM counts as in effect, or not yet expired.
  private static let listWindowSeconds: TimeInterval = 3600

  /// Which part of the downloaded-NOTAM list this NOTAM belongs in.
  ///
  /// - Parameters:
  ///   - plannedTime: When the flight departs or arrives.
  ///   - canFill: Whether the app can fill the NOTAM editor in from this NOTAM.
  public func listTier(at plannedTime: Date, canFill: Bool) -> ListTier {
    if hasExpired(before: plannedTime, windowInterval: Self.listWindowSeconds) { return .expired }
    if canFill { return .fillable }
    return isRelevant ? .relevant : .other
  }

  fileprivate func isInEffect(at plannedTime: Date) -> Bool {
    isEffective(within: plannedTime, windowInterval: Self.listWindowSeconds)
  }

  /// Which part of the downloaded-NOTAM list a NOTAM belongs in, in list order.
  public enum ListTier: Comparable, Sendable {
    /// The app can fill the NOTAM editor in from it.
    case fillable

    /// It likely affects runway performance, but the app can't fill the editor in from it.
    case relevant

    /// Any other NOTAM still in effect or yet to take effect.
    case other

    /// It expired more than an hour before the planned time, so nothing it says applies to the flight.
    case expired
  }
}

extension Sequence<NOTAMResponse> {
  /**
   These NOTAMs in the order the downloaded-NOTAM list shows them.

   NOTAMs are grouped by ``NOTAMResponse/ListTier``. Within a group, NOTAMs in effect around the
   planned time come before those yet to take effect, and aerodrome NOTAMs before the rest; those in
   effect are newest first, those yet to take effect soonest first. Expired NOTAMs are most recently
   expired first.

   - Parameters:
     - plannedTime: When the flight departs or arrives.
     - canFill: Whether the app can fill the NOTAM editor in from a NOTAM.
   */
  public func sortedForList(
    at plannedTime: Date,
    canFill: (NOTAMResponse) -> Bool
  ) -> [NOTAMResponse] {
    map { NOTAMListPosition($0, at: plannedTime, canFill: canFill($0)) }
      .sorted(by: NOTAMListPosition.isInOrder)
      .map(\.notam)
  }
}

/// A NOTAM, with everything that places it in the downloaded-NOTAM list worked out once.
private struct NOTAMListPosition {
  let notam: NOTAMResponse,
    tier: NOTAMResponse.ListTier,
    isInEffect: Bool

  init(_ notam: NOTAMResponse, at plannedTime: Date, canFill: Bool) {
    self.notam = notam
    tier = notam.listTier(at: plannedTime, canFill: canFill)
    isInEffect = notam.isInEffect(at: plannedTime)
  }

  /// Whether `lhs` comes before `rhs` in the list.
  static func isInOrder(_ lhs: Self, _ rhs: Self) -> Bool {
    if lhs.tier != rhs.tier { return lhs.tier < rhs.tier }
    if lhs.tier == .expired { return Self.expiredMoreRecently(lhs.notam, than: rhs.notam) }
    if lhs.isInEffect != rhs.isInEffect { return lhs.isInEffect }
    if lhs.notam.isAerodromeRelated != rhs.notam.isAerodromeRelated {
      return lhs.notam.isAerodromeRelated
    }
    return lhs.isInEffect
      ? lhs.notam.effectiveStart > rhs.notam.effectiveStart
      : lhs.notam.effectiveStart < rhs.notam.effectiveStart
  }

  private static func expiredMoreRecently(_ lhs: NOTAMResponse, than rhs: NOTAMResponse) -> Bool {
    guard let lhsEnd = lhs.effectiveEnd, let rhsEnd = rhs.effectiveEnd else { return false }
    return lhsEnd > rhsEnd
  }
}
