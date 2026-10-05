public import Foundation

extension NOTAMProposal {

  // MARK: - Filling

  /// The part of this proposal that `notamID` proposes.
  public func from(notamID: String) -> Self {
    var proposal = Self()
    proposal.takeoffShortening = takeoffShortening.proposed(by: notamID)
    proposal.takeoffShorteningLocation = takeoffShorteningLocation.proposed(by: notamID)
    proposal.landingShortening = landingShortening.proposed(by: notamID)
    proposal.landingShorteningLocation = landingShorteningLocation.proposed(by: notamID)
    proposal.contamination = contamination.proposed(by: notamID)
    proposal.obstacle = obstacle.proposed(by: notamID)
    proposal.closedForTakeoffBy = closedForTakeoffBy.filter { $0.notamID == notamID }
    proposal.closedForLandingBy = closedForLandingBy.filter { $0.notamID == notamID }
    return proposal
  }

  /// The part of this proposal that fills a field the NOTAM editor shows for `operation`.
  ///
  /// Takeoff takes the takeoff shortening and the obstacle; landing takes the landing shortening
  /// and the contamination. A closure fills nothing, so it's dropped from both.
  public func fields(for operation: Operation) -> Self {
    var proposal = Self()
    switch operation {
      case .takeoff:
        proposal.takeoffShortening = takeoffShortening
        proposal.takeoffShorteningLocation = takeoffShorteningLocation
        proposal.obstacle = obstacle
      case .landing:
        proposal.landingShortening = landingShortening
        proposal.landingShorteningLocation = landingShorteningLocation
        proposal.contamination = contamination
    }
    return proposal
  }

  /// Writes this proposal's first value for each of `operation`'s fields into `notam`.
  ///
  /// Fields the proposal has no value for keep what the pilot entered, so a shortening entered by
  /// hand survives a filled-in obstacle.
  ///
  /// - Returns: What to hand ``NOTAMRestoration/restore(_:)`` to put `notam` back as it was.
  @discardableResult
  public func fill(_ notam: NOTAM, for operation: Operation) -> NOTAMRestoration {
    let restoration = NOTAMRestoration(notam)
    let proposal = fields(for: operation)
    switch operation {
      case .takeoff:
        if let value = proposal.takeoffShortening.first?.value {
          notam.takeoffDistanceShortening = value
        }
        if let value = proposal.takeoffShorteningLocation.first?.value {
          notam.takeoffShorteningLocation = value
        }
        if let value = proposal.obstacle.first?.value {
          notam.obstacleHeight = value.height
          notam.obstacleDistance = value.distance
        }
      case .landing:
        if let value = proposal.landingShortening.first?.value {
          notam.landingDistanceShortening = value
        }
        if let value = proposal.landingShorteningLocation.first?.value {
          notam.landingShorteningLocation = value
        }
        if let value = proposal.contamination.first?.value { notam.contamination = value }
    }
    return restoration
  }
}

/// A ``NOTAM``'s values as they were before a proposal filled it in, to undo the fill.
public struct NOTAMRestoration: Sendable, Equatable {
  private let takeoffShortening: Measurement<UnitLength>,
    takeoffShorteningLocation: ShorteningLocation,
    landingShortening: Measurement<UnitLength>,
    landingShorteningLocation: ShorteningLocation,
    contamination: Contamination?,
    obstacleHeight: Measurement<UnitLength>,
    obstacleDistance: Measurement<UnitLength>

  init(_ notam: NOTAM) {
    takeoffShortening = notam.takeoffDistanceShortening
    takeoffShorteningLocation = notam.takeoffShorteningLocation
    landingShortening = notam.landingDistanceShortening
    landingShorteningLocation = notam.landingShorteningLocation
    contamination = notam.contamination
    obstacleHeight = notam.obstacleHeight
    obstacleDistance = notam.obstacleDistance
  }

  /// Puts `notam`'s values back as they were.
  public func restore(_ notam: NOTAM) {
    notam.takeoffDistanceShortening = takeoffShortening
    notam.takeoffShorteningLocation = takeoffShorteningLocation
    notam.landingDistanceShortening = landingShortening
    notam.landingShorteningLocation = landingShorteningLocation
    notam.contamination = contamination
    notam.obstacleHeight = obstacleHeight
    notam.obstacleDistance = obstacleDistance
  }
}

extension Array {
  fileprivate func proposed<Value>(by notamID: String) -> Self where Element == Candidate<Value> {
    filter { $0.sources.contains { $0.notamID == notamID } }
  }
}
