public import Foundation
import NOTAMParsing

/// Values the downloaded NOTAMs propose for one runway direction's ``NOTAM``, for the pilot to
/// confirm.
///
/// Only NOTAMs in a fixed report format propose anything: runway condition reports (FAA FICON,
/// Canadian RSC, ICAO SNOWTAM) propose the runway's contamination, and FAA obstacle reports an
/// obstacle off the end a takeoff leaves from. They're read exactly, by `NOTAMParsing`'s
/// `FormattedReportParser`, or not at all.
///
/// A proposal never changes a ``NOTAM`` or feeds a calculation; confirming it is the pilot's act.
/// Each field holds every distinct value the NOTAMs propose, with the NOTAMs that propose it, so
/// NOTAMs that disagree are shown as alternatives rather than resolved.
public struct NOTAMProposal: Sendable, Equatable {

  // MARK: - Instance Properties

  /// The runway's surface condition.
  public var contamination: [Candidate<Contamination>] = []

  /// An obstacle off the departure end, ahead of a takeoff in this runway direction.
  public var obstacle: [Candidate<ProposedObstacle>] = []

  /// Whether the NOTAMs propose nothing for this runway direction.
  public var isEmpty: Bool { self == Self() }

  // MARK: - Initializers

  /// An empty proposal.
  public init() {}

  /// What `notams` propose for `runway`.
  public init(notams: [NOTAMResponse], runway: ProposalRunway) {
    self.init()
    let parser = FormattedReportParser()
    for notam in notams {
      guard let report = parser.parse(notamText: notam.notamText) else { continue }
      merge(NOTAMProposalMapper.proposal(from: report, notamID: notam.notamId, for: runway))
    }
  }

  // MARK: - Type Methods

  /// What `notams` propose for `runway`, read off the main actor.
  @concurrent
  public static func reading(_ notams: [NOTAMResponse], for runway: ProposalRunway) async -> Self {
    Self(notams: notams, runway: runway)
  }

  // MARK: - Instance Methods

  /// Adds `other`'s candidates to this proposal's, joining candidates that propose the same value.
  public mutating func merge(_ other: Self) {
    contamination.merge(other.contamination)
    obstacle.merge(other.obstacle)
  }
}

/// An obstacle a NOTAM places ahead of a takeoff, as the NOTAM editor records one.
public struct ProposedObstacle: Sendable, Hashable {

  // MARK: - Instance Properties

  /// The obstacle's height above the departure end.
  public let height: Measurement<UnitLength>

  /// How far beyond the departure end the obstacle stands.
  public let distance: Measurement<UnitLength>

  // MARK: - Initializers

  /// Creates an obstacle.
  public init(height: Measurement<UnitLength>, distance: Measurement<UnitLength>) {
    self.height = height
    self.distance = distance
  }
}

/// The runway direction a proposal is for: what proposing needs of a ``Runway``.
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

  // MARK: - Initializers

  /// - Parameters:
  ///   - name: The direction's name.
  ///   - reciprocalName: The reciprocal direction's name.
  ///   - trueHeadingDegrees: The direction's true heading, in degrees.
  ///   - departureEndElevation: The elevation of the end a takeoff leaves from.
  public init(
    name: String,
    reciprocalName: String?,
    trueHeadingDegrees: Double,
    departureEndElevation: Measurement<UnitLength>
  ) {
    self.name = name
    self.reciprocalName = reciprocalName
    self.trueHeadingDegrees = trueHeadingDegrees
    self.departureEndElevation = departureEndElevation
  }

  /// The facts about `runway` a proposal needs. Its departure end is its reciprocal's threshold.
  public init(_ runway: Runway) {
    self.init(
      name: runway.name,
      reciprocalName: runway.reciprocalName,
      trueHeadingDegrees: runway.trueHeading.converted(to: .degrees).value,
      departureEndElevation: (runway.reciprocal ?? runway).elevationOrAirportElevation
    )
  }
}

/// One value proposed for a field, and the NOTAMs that propose it.
public struct Candidate<Value: Hashable & Sendable>: Sendable, Hashable {

  // MARK: - Instance Properties

  /// The proposed value.
  public let value: Value

  /// The identifiers (``NOTAMResponse/notamId``) of the NOTAMs that propose it.
  public private(set) var notamIDs: [String]

  // MARK: - Initializers

  /// A value proposed by the NOTAM identified by `notamID`.
  public init(_ value: Value, from notamID: String) {
    self.value = value
    notamIDs = [notamID]
  }

  // MARK: - Instance Methods

  fileprivate mutating func add(_ newNOTAMIDs: [String]) {
    notamIDs += newNOTAMIDs.filter { !notamIDs.contains($0) }
  }
}

extension Array {
  fileprivate mutating func merge<Value>(_ others: [Candidate<Value>])
  where Element == Candidate<Value> {
    for other in others {
      if let index = firstIndex(where: { $0.value == other.value }) {
        self[index].add(other.notamIDs)
      } else {
        append(other)
      }
    }
  }
}
