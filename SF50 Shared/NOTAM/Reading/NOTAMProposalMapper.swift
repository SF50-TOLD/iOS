public import Foundation
public import NOTAMModel
import NOTAMParsing

/// Runway designators as NOTAM readings write them (SF50 Shared has a ``RunwayDesignator`` of its own).
private typealias NOTAMDesignator = NOTAMParsing.RunwayDesignator

/// Turns a NOTAM's reading into what it proposes for one runway direction.
///
/// The rules are fixed and deterministic, so the same reading always proposes the same values:
///
/// - Declared distances shorten a direction by the difference from its published TORA and LDA
///   (the runway's length where none is published). Without them, a partial closure's closed length
///   shortens both takeoff and landing, and a displaced threshold shortens landing by how much it
///   exceeds the published displacement.
/// - A closed end becomes a ``ShorteningLocation``: `FIRST`/`LAST` relative to the effect's
///   runway (flipped for its reciprocal), a runway end by name, or a compass end by the runway's
///   heading. An end it can't place isn't proposed.
/// - RwyCC codes propose the lowest code reported, and nothing when a third reports code 0, which
///   has no AFM figures. Without codes, the contaminants propose the AFM category of the worst of
///   them, and nothing when their coverages add up to 25% or less, which earns no codes, or when
///   one of them falls in no AFM category.
/// - Only a formatted report proposes an obstacle: its distance and its height above the departure
///   end (its elevation less the end's, or its height above ground when it gives no elevation), for
///   the direction whose takeoff leaves from the runway end its reference names (`DEP END RWY 30`
///   for runway 30, `APCH END RWY 12L` for runway 30R), when its compass direction is within one
///   point of that runway's heading and it stands above the departure end. A model reading's
///   obstacles propose nothing.
/// - A closure is reported through ``NOTAMProposal/closedForTakeoffBy`` and
///   ``NOTAMProposal/closedForLandingBy``.
///
/// Only fields in the reading's ``NOTAMExtractor/Reading/proposableFields`` are proposed. A
/// cancelled NOTAM, and an effect that names no runway, propose nothing.
public enum NOTAMProposalMapper {

  // MARK: - Type Properties

  /// A shortening smaller than this is rounding in the published or NOTAM values, not a change.
  private static let negligibleShortening = Measurement(value: 1, unit: UnitLength.meters)

  /// Headings within this of perpendicular to a compass end can't say which end is meant.
  private static let ambiguousEndTolerance = 10.0

  /// How far an obstacle's compass direction may lie from the runway heading and still be ahead of
  /// the takeoff: one point of the 16-point compass either side.
  private static let departureToleranceDegrees = 22.5

  /// The most of a runway contaminants may cover and the runway still earn no condition codes.
  private static let uncodedCoveragePercent = 25.0

  // MARK: - Type Methods

  /// What `reading` proposes for `runway`.
  ///
  /// - Parameters:
  ///   - reading: One NOTAM's reading.
  ///   - notamID: The NOTAM's identifier, recorded as each value's source.
  ///   - runway: The runway direction being proposed for.
  public static func proposal(
    from reading: NOTAMExtractor.Reading,
    notamID: String,
    for runway: ProposalRunway
  ) -> NOTAMProposal {
    guard !reading.extraction.isCanceled else { return NOTAMProposal() }
    let source = ProposalSource(notamID: notamID, reader: reading.source)
    var proposal = reading.extraction.effects
      .filter { effect in effect.runway.map { NOTAMDesignator.names(runway.name, in: $0) } ?? false
      }
      .reduce(into: NOTAMProposal()) { proposal, effect in
        proposal.merge(
          EffectMapping(
            effect: effect,
            runway: runway,
            fields: reading.proposableFields,
            source: source
          ).proposal
        )
      }
    proposal.obstacle = (reading.report?.effects ?? []).compactMap(\.obstacle)
      .compactMap { departureObstacle($0, for: runway) }
      .map { Candidate($0, from: source) }
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

  /// How much of the runway `contaminants` cover, as a percentage: the sum of their coverages,
  /// which overstates a report by thirds rather than understate it. Coverage a report doesn't state
  /// counts for none.
  private static func coveragePercent(of contaminants: [NOTAMExtraction.Contaminant]) -> Double {
    contaminants.reduce(0) { $0 + Double($1.coveragePercent ?? 0) }
  }

  /// Whether a takeoff on `runway` leaves from `end`: its own departure end, or the approach end of
  /// its reciprocal.
  private static func takesOff(_ runway: ProposalRunway, over end: FormattedReport.RunwayEnd)
    -> Bool
  {
    switch end.end {
      case .departure: NOTAMDesignator.names(runway.name, in: end.runway)
      case .approach:
        runway.reciprocalName.map { NOTAMDesignator.names($0, in: end.runway) } ?? false
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

  /// Where a closed end lies relative to `runway`'s direction, or `nil` when it can't be placed.
  ///
  /// - Parameters:
  ///   - closedEnd: The end of the effect's `NOTAMExtraction.PartialClosure`.
  ///   - effectRunway: The effect's runway, which `FIRST` and `LAST` are relative to.
  ///   - runway: The runway direction being proposed for.
  static func location(
    ofClosedEnd closedEnd: String,
    effectRunway: String,
    on runway: ProposalRunway
  ) -> ShorteningLocation? {
    switch closedEnd {
      case "thresholdEnd", "departureEnd":
        relativeLocation(
          closedEnd == "thresholdEnd" ? .thresholdEnd : .departureEnd,
          effectRunway,
          runway
        )
      default:
        if let designator = NOTAMDesignator.normalize(closedEnd), !designator.contains("/") {
          designatedEndLocation(designator, on: runway)
        } else {
          compassEndLocation(closedEnd, on: runway)
        }
    }
  }

  private static func relativeLocation(
    _ location: ShorteningLocation,
    _ effectRunway: String,
    _ runway: ProposalRunway
  ) -> ShorteningLocation? {
    let directions = NOTAMDesignator.directions(of: effectRunway)
    guard directions.count == 1, let direction = directions.first else { return nil }
    if NOTAMDesignator.names(runway.name, in: direction) { return location }
    guard let reciprocal = runway.reciprocalName, NOTAMDesignator.names(reciprocal, in: direction)
    else { return nil }
    return location.flipped
  }

  private static func designatedEndLocation(_ end: String, on runway: ProposalRunway)
    -> ShorteningLocation?
  {
    if NOTAMDesignator.names(runway.name, in: end) { return .thresholdEnd }
    if let reciprocal = runway.reciprocalName, NOTAMDesignator.names(reciprocal, in: end) {
      return .departureEnd
    }
    return nil
  }

  /// The departure end lies along the runway's heading and the threshold end opposite it.
  private static func compassEndLocation(_ end: String, on runway: ProposalRunway)
    -> ShorteningLocation?
  {
    guard let bearing = CompassPoint(rawValue: end)?.bearing else { return nil }
    let offset = abs(
      (bearing - runway.trueHeadingDegrees + 540).truncatingRemainder(dividingBy: 360) - 180
    )
    if offset < 90 - ambiguousEndTolerance { return .departureEnd }
    if offset > 90 + ambiguousEndTolerance { return .thresholdEnd }
    return nil
  }

  // MARK: - Nested Types

  /// What one effect proposes for one runway direction.
  private struct EffectMapping {
    let effect: NOTAMExtraction.RunwayEffect
    let runway: ProposalRunway
    let fields: Set<ProposableField>
    let source: ProposalSource

    var proposal: NOTAMProposal {
      var proposal = NOTAMProposal()
      if fields.contains(.closure) {
        if effect.closure == .takeoff || effect.closure == .both {
          proposal.closedForTakeoffBy = [source]
        }
        if effect.closure == .landing || effect.closure == .both {
          proposal.closedForLandingBy = [source]
        }
      }
      let location = closedEndLocation
      if let shortening = takeoffShortening {
        proposal.takeoffShortening = [Candidate(shortening, from: source)]
        proposal.takeoffShorteningLocation = location.map { [Candidate($0, from: source)] } ?? []
      }
      if let landing = landingShortening(closedEnd: location) {
        proposal.landingShortening = [Candidate(landing.shortening, from: source)]
        proposal.landingShorteningLocation =
          landing.location.map { [Candidate($0, from: source)] } ?? []
      }
      proposal.contamination = contamination.map { [Candidate($0, from: source)] } ?? []
      return proposal
    }

    private var closedEndLocation: ShorteningLocation? {
      guard fields.contains(.closedEnd), let closedEnd = effect.partialClosure?.end,
        let effectRunway = effect.runway
      else { return nil }
      return NOTAMProposalMapper.location(
        ofClosedEnd: closedEnd,
        effectRunway: effectRunway,
        on: runway
      )
    }

    private var partialClosureLength: Measurement<UnitLength>? {
      guard fields.contains(.closedLength) else { return nil }
      return effect.partialClosure?.length?.measurement
    }

    private var takeoffShortening: Measurement<UnitLength>? {
      if fields.contains(.TORA), let tora = effect.declaredDistances?.TORA?.measurement {
        return significant(runway.publishedTakeoffRun - tora)
      }
      return partialClosureLength.flatMap(significant)
    }

    private var contamination: Contamination? {
      guard let condition = effect.surfaceCondition else { return nil }
      if fields.contains(.rwyCC), let lowest = condition.rwyCC?.min() {
        return lowest > 0 ? UInt8(exactly: lowest).map { .rwyCC($0) } : nil
      }
      guard fields.contains(.contaminants),
        NOTAMProposalMapper.coveragePercent(of: condition.contaminants)
          > NOTAMProposalMapper.uncodedCoveragePercent
      else { return nil }
      let categories = condition.contaminants.map(\.contamination)
      guard categories.allSatisfy({ $0 != nil }) else { return nil }
      return categories.compactMap(\.self).max { $0.severity < $1.severity }
    }

    private func landingShortening(closedEnd: ShorteningLocation?)
      -> (shortening: Measurement<UnitLength>, location: ShorteningLocation?)?
    {
      if fields.contains(.LDA), let lda = effect.declaredDistances?.LDA?.measurement {
        return significant(runway.publishedLandingDistance - lda).map { ($0, closedEnd) }
      }
      if let closed = partialClosureLength.flatMap(significant) { return (closed, closedEnd) }
      guard fields.contains(.thresholdDisplacement),
        let displacement = effect.thresholdDisplacement?.measurement
      else { return nil }
      return significant(displacement - runway.publishedDisplacement).map { ($0, .thresholdEnd) }
    }

    private func significant(_ shortening: Measurement<UnitLength>) -> Measurement<UnitLength>? {
      shortening >= NOTAMProposalMapper.negligibleShortening ? shortening : nil
    }
  }

  /// A compass point a NOTAM names a runway end by.
  private enum CompassPoint: String {
    case N, NE, E, SE, S, SW, W, NW

    var bearing: Double {
      switch self {
        case .N: 0
        case .NE: 45
        case .E: 90
        case .SE: 135
        case .S: 180
        case .SW: 225
        case .W: 270
        case .NW: 315
      }
    }
  }
}

/// The runway direction a proposal is for: what the mapper needs of a ``Runway``.
public struct ProposalRunway: Sendable, Equatable {

  // MARK: - Instance Properties

  /// The direction's name, as the nav data writes it (`9R`, `28L`).
  public let name: String

  /// The reciprocal direction's name, if the runway has one.
  public let reciprocalName: String?

  /// The direction's true heading, in degrees.
  public let trueHeadingDegrees: Double

  /// The elevation of the end a takeoff in this direction leaves from.
  public let departureEndElevation: Measurement<UnitLength>

  /// The published takeoff run available, or the runway's length.
  public let publishedTakeoffRun: Measurement<UnitLength>

  /// The published landing distance available, or the runway's length.
  public let publishedLandingDistance: Measurement<UnitLength>

  /// The published displaced-threshold distance, or zero.
  public let publishedDisplacement: Measurement<UnitLength>

  // MARK: - Initializers

  /// - Parameters:
  ///   - name: The direction's name.
  ///   - reciprocalName: The reciprocal direction's name.
  ///   - trueHeadingDegrees: The direction's true heading, in degrees.
  ///   - departureEndElevation: The elevation of the end a takeoff leaves from.
  ///   - publishedTakeoffRun: The published TORA, or the runway's length.
  ///   - publishedLandingDistance: The published LDA, or the runway's length.
  ///   - publishedDisplacement: The published displaced-threshold distance, or zero.
  public init(
    name: String,
    reciprocalName: String?,
    trueHeadingDegrees: Double,
    departureEndElevation: Measurement<UnitLength>,
    publishedTakeoffRun: Measurement<UnitLength>,
    publishedLandingDistance: Measurement<UnitLength>,
    publishedDisplacement: Measurement<UnitLength> = .init(value: 0, unit: .meters)
  ) {
    self.name = name
    self.reciprocalName = reciprocalName
    self.trueHeadingDegrees = trueHeadingDegrees
    self.departureEndElevation = departureEndElevation
    self.publishedTakeoffRun = publishedTakeoffRun
    self.publishedLandingDistance = publishedLandingDistance
    self.publishedDisplacement = publishedDisplacement
  }

  /// The facts about `runway` a proposal needs. Its departure end is its reciprocal's threshold.
  public init(_ runway: Runway) {
    self.init(
      name: runway.name,
      reciprocalName: runway.reciprocalName,
      trueHeadingDegrees: runway.trueHeading.converted(to: .degrees).value,
      departureEndElevation: (runway.reciprocal ?? runway).elevationOrAirportElevation,
      publishedTakeoffRun: runway.takeoffRunOrLength,
      publishedLandingDistance: runway.landingDistanceOrLength,
      publishedDisplacement: runway.displacedThresholdDistance ?? .init(value: 0, unit: .meters)
    )
  }
}

extension ShorteningLocation {
  /// The same end, seen from the reciprocal direction.
  fileprivate var flipped: Self { self == .thresholdEnd ? .departureEnd : .thresholdEnd }
}

extension NOTAMExtraction.Length {
  fileprivate var measurement: Measurement<UnitLength> {
    .init(value: value, unit: unit == .ft ? .feet : .meters)
  }
}

extension NOTAMExtraction.Contaminant {
  /// The AFM category this contaminant falls in, or `nil` when it fits none (frost, layered
  /// contaminants) or needs a depth it doesn't state.
  fileprivate var contamination: Contamination? {
    let depth = depth.map {
      Measurement(value: $0.value, unit: $0.unit == .in ? UnitLength.inches : .millimeters)
    }
    switch type {
      case .water, .slush: return depth.flatMap { $0.value > 0 ? .waterOrSlush(depth: $0) : nil }
      case .wetSnow: return depth.flatMap { $0.value > 0 ? .slushOrWetSnow(depth: $0) : nil }
      case .drySnow: return .drySnow
      case .compactedSnow, .ice: return .compactSnow
      case .wet: return .wetRunway
      default: return nil
    }
  }
}

extension Contamination {
  /// Orders the categories a runway's contaminants propose, so the worst is proposed: a contaminant
  /// the AFM tabulates by depth over compacted snow or ice, over dry snow, over a wet runway.
  var severity: (Int, Double) {
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
