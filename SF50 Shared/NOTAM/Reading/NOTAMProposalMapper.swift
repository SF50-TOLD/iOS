import Foundation
import NOTAMParsing

/// Runway designators as reports write them (SF50 Shared has a ``RunwayDesignator`` of its own).
private typealias ReportDesignator = NOTAMParsing.RunwayDesignator

/// Turns a formatted report into what it proposes for one runway direction.
///
/// The rules are fixed and deterministic, so the same report always proposes the same values:
///
/// - A surface condition proposes for the directions its runway names; a runway pair names both.
///   It proposes the lowest runway condition code reported, and nothing when a third reports code
///   0, which has no AFM figures. Without codes, it proposes the AFM category of its worst
///   contaminant, and nothing when the contaminants cover 25% of the runway or less, which earns no
///   codes, or when one of them falls in no AFM category.
/// - An obstacle proposes its height above the departure end and its distance only for the
///   direction whose takeoff leaves from the runway end its reference names, `DEP END RWY 30` for
///   runway 30 and `APCH END RWY 12L` for runway 30R, and only when it lies ahead of that takeoff,
///   within one compass point of the runway's heading. Its height is its elevation less the
///   departure end's, or its height above ground when the report gives no elevation. An obstacle
///   the report doesn't place off a runway end that way, or that doesn't stand above the departure
///   end, proposes nothing.
enum NOTAMProposalMapper {

  // MARK: - Type Properties

  /// The most of a runway contaminants may cover and the runway still earn no condition codes.
  private static let uncodedCoveragePercent = 25.0

  /// How far an obstacle's compass direction may lie from the runway heading and still be ahead of
  /// the takeoff: one point of the 16-point compass either side.
  private static let departureToleranceDegrees = 22.5

  // MARK: - Type Methods

  /// What `report` proposes for `runway`.
  ///
  /// - Parameters:
  ///   - report: One NOTAM's report.
  ///   - notamID: The NOTAM's identifier, recorded as each value's source.
  ///   - runway: The runway direction being proposed for.
  static func proposal(from report: FormattedReport, notamID: String, for runway: ProposalRunway)
    -> NOTAMProposal
  {
    report.effects.reduce(into: NOTAMProposal()) {
      $0.merge(proposal(from: $1, notamID: notamID, for: runway))
    }
  }

  private static func proposal(
    from effect: FormattedReport.RunwayEffect,
    notamID: String,
    for runway: ProposalRunway
  ) -> NOTAMProposal {
    var proposal = NOTAMProposal()
    if let effectRunway = effect.runway, ReportDesignator.names(runway.name, in: effectRunway),
      let contamination = effect.surfaceCondition.flatMap(contamination(from:))
    {
      proposal.contamination = [.init(contamination, from: notamID)]
    }
    if let obstacle = effect.obstacle.flatMap({ departureObstacle($0, for: runway) }) {
      proposal.obstacle = [.init(obstacle, from: notamID)]
    }
    return proposal
  }

  private static func departureObstacle(
    _ obstacle: FormattedReport.Obstacle,
    for runway: ProposalRunway
  ) -> ProposedObstacle? {
    guard let end = obstacle.runwayEnd, takesOff(runway, over: end),
      isAhead(obstacle.direction, of: runway),
      let height = height(of: obstacle, aboveDepartureEndOf: runway), height.value > 0
    else { return nil }
    return .init(height: height, distance: obstacle.distance)
  }

  private static func height(
    of obstacle: FormattedReport.Obstacle,
    aboveDepartureEndOf runway: ProposalRunway
  ) -> Measurement<UnitLength>? {
    obstacle.heightMSL.map { $0 - runway.departureEndElevation } ?? obstacle.heightAGL
  }

  /// Whether a takeoff on `runway` leaves from `end`: its own departure end, or the approach end of
  /// its reciprocal.
  private static func takesOff(_ runway: ProposalRunway, over end: FormattedReport.RunwayEnd)
    -> Bool
  {
    switch end.end {
      case .departure: ReportDesignator.names(runway.name, in: end.runway)
      case .approach:
        runway.reciprocalName.map { ReportDesignator.names($0, in: end.runway) } ?? false
    }
  }

  private static func isAhead(
    _ direction: FormattedReport.CompassPoint,
    of runway: ProposalRunway
  ) -> Bool {
    let offset = abs(
      (direction.degrees - runway.trueHeadingDegrees + 540).truncatingRemainder(dividingBy: 360)
        - 180
    )
    return offset <= departureToleranceDegrees
  }

  private static func contamination(from condition: FormattedReport.SurfaceCondition)
    -> Contamination?
  {
    if let codes = condition.rwyCC {
      return codes.min().flatMap(UInt8.init(exactly:)).flatMap { $0 > 0 ? .rwyCC($0) : nil }
    }
    guard coveragePercent(of: condition.contaminants) > uncodedCoveragePercent else { return nil }
    let categories = condition.contaminants.map(\.contamination)
    guard categories.allSatisfy({ $0 != nil }) else { return nil }
    return categories.compactMap(\.self).max { $0.severity < $1.severity }
  }

  /// How much of the runway `contaminants` cover, as a percentage: those reported by thirds count
  /// for a third of the runway each. Coverage a report doesn't state counts for none.
  private static func coveragePercent(of contaminants: [FormattedReport.Contaminant]) -> Double {
    contaminants.reduce(0) {
      $0 + Double($1.coveragePercent ?? 0) / ($1.runwayThird == nil ? 1 : 3)
    }
  }
}

extension FormattedReport.Contaminant {
  /// The AFM category this contaminant falls in, or `nil` when it fits none (frost, layered
  /// contaminants) or needs a depth it doesn't state.
  fileprivate var contamination: Contamination? {
    switch type {
      case .water, .slush: depth.flatMap { $0.value > 0 ? .waterOrSlush(depth: $0) : nil }
      case .wetSnow: depth.flatMap { $0.value > 0 ? .slushOrWetSnow(depth: $0) : nil }
      case .drySnow: .drySnow
      case .compactedSnow, .ice: .compactSnow
      case .wet: .wetRunway
      default: nil
    }
  }
}

extension Contamination {
  /// Orders the categories a runway's contaminants propose, so the worst is proposed: a contaminant
  /// the AFM tabulates by depth over compacted snow or ice, over dry snow, over a wet runway.
  fileprivate var severity: (Int, Double) {
    switch self {
      case .waterOrSlush(let depth), .slushOrWetSnow(let depth):
        (4, depth.converted(to: .inches).value)
      case .compactSnow: (3, 0)
      case .drySnow: (2, 0)
      case .wetRunway: (1, 0)
      case .rwyCC: (0, 0)
    }
  }
}
