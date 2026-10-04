public import Foundation

extension NOTAMProposal {

  // MARK: - Filling

  /// The part of this proposal that `notamID` proposes.
  public func from(notamID: String) -> Self {
    var proposal = Self()
    proposal.contamination = contamination.proposed(by: notamID)
    proposal.obstacle = obstacle.proposed(by: notamID)
    return proposal
  }

  /// The part of this proposal that fills a field the NOTAM editor shows for `operation`: the
  /// obstacle for takeoff, and the contamination for landing.
  public func fields(for operation: Operation) -> Self {
    var proposal = Self()
    switch operation {
      case .takeoff: proposal.obstacle = obstacle
      case .landing: proposal.contamination = contamination
    }
    return proposal
  }

  /// Writes this proposal's first value for `operation`'s field into `notam`.
  ///
  /// A field the proposal has no value for keeps what the pilot entered, and so do the fields it
  /// doesn't propose, so a shortening entered by hand survives a filled-in obstacle.
  ///
  /// - Returns: What to hand ``NOTAMRestoration/restore(_:)`` to put `notam` back as it was.
  @discardableResult
  public func fill(_ notam: NOTAM, for operation: Operation) -> NOTAMRestoration {
    let restoration = NOTAMRestoration(notam)
    switch operation {
      case .takeoff:
        if let value = obstacle.first?.value {
          notam.obstacleHeight = value.height
          notam.obstacleDistance = value.distance
        }
      case .landing:
        if let value = contamination.first?.value { notam.contamination = value }
    }
    return restoration
  }
}

/// A ``NOTAM``'s values as they were before a proposal filled it in, to undo the fill.
public struct NOTAMRestoration: Sendable, Equatable {
  private let contamination: Contamination?,
    obstacleHeight: Measurement<UnitLength>,
    obstacleDistance: Measurement<UnitLength>

  init(_ notam: NOTAM) {
    contamination = notam.contamination
    obstacleHeight = notam.obstacleHeight
    obstacleDistance = notam.obstacleDistance
  }

  /// Puts `notam`'s values back as they were.
  public func restore(_ notam: NOTAM) {
    notam.contamination = contamination
    notam.obstacleHeight = obstacleHeight
    notam.obstacleDistance = obstacleDistance
  }
}

extension Array {
  fileprivate func proposed<Value>(by notamID: String) -> Self where Element == Candidate<Value> {
    filter { $0.notamIDs.contains(notamID) }
  }
}
