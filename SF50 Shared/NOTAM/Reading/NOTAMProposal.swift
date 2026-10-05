public import Foundation

/// Values the downloaded NOTAMs propose for one runway direction's ``NOTAM``, for the pilot to
/// confirm.
///
/// A proposal never changes a ``NOTAM`` or feeds a calculation; confirming it is the pilot's act.
/// Each field holds every distinct value the NOTAMs propose, with the NOTAMs that propose it, so
/// NOTAMs that disagree are shown as alternatives rather than resolved.
public struct NOTAMProposal: Sendable, Equatable {

  // MARK: - Instance Properties

  /// How much shorter the takeoff run is than published.
  public var takeoffShortening: [Candidate<Measurement<UnitLength>>] = []

  /// Which end of the runway the takeoff shortening is at.
  public var takeoffShorteningLocation: [Candidate<ShorteningLocation>] = []

  /// How much shorter the landing distance is than published.
  public var landingShortening: [Candidate<Measurement<UnitLength>>] = []

  /// Which end of the runway the landing shortening is at.
  public var landingShorteningLocation: [Candidate<ShorteningLocation>] = []

  /// The runway's surface condition.
  public var contamination: [Candidate<Contamination>] = []

  /// An obstacle off the departure end, ahead of a takeoff in this runway direction.
  public var obstacle: [Candidate<ProposedObstacle>] = []

  /// NOTAMs that close the runway direction for takeoff. The ``NOTAM`` model has no closure, so
  /// this is advice to show, not a value to confirm.
  public var closedForTakeoffBy: [ProposalSource] = []

  /// NOTAMs that close the runway direction for landing, as advice to show.
  public var closedForLandingBy: [ProposalSource] = []

  /// Whether the NOTAMs propose nothing for this runway direction.
  public var isEmpty: Bool { self == Self() }

  // MARK: - Initializers

  /// An empty proposal.
  public init() {}

  // MARK: - Instance Methods

  /// Adds `other`'s candidates to this proposal's, joining candidates that propose the same value.
  public mutating func merge(_ other: Self) {
    takeoffShortening.merge(other.takeoffShortening)
    takeoffShorteningLocation.merge(other.takeoffShorteningLocation)
    landingShortening.merge(other.landingShortening)
    landingShorteningLocation.merge(other.landingShorteningLocation)
    contamination.merge(other.contamination)
    obstacle.merge(other.obstacle)
    closedForTakeoffBy += other.closedForTakeoffBy.filter { !closedForTakeoffBy.contains($0) }
    closedForLandingBy += other.closedForLandingBy.filter { !closedForLandingBy.contains($0) }
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

/// One value proposed for a field, and the NOTAMs that propose it.
public struct Candidate<Value: Hashable & Sendable>: Sendable, Hashable {

  // MARK: - Instance Properties

  /// The proposed value.
  public let value: Value

  /// The NOTAMs that propose it.
  public private(set) var sources: [ProposalSource]

  // MARK: - Initializers

  /// A value proposed by one NOTAM.
  public init(_ value: Value, from source: ProposalSource) {
    self.value = value
    sources = [source]
  }

  // MARK: - Instance Methods

  fileprivate mutating func add(_ newSources: [ProposalSource]) {
    sources += newSources.filter { !sources.contains($0) }
  }
}

/// A NOTAM that proposes a value, and what read it.
public struct ProposalSource: Sendable, Hashable {

  // MARK: - Instance Properties

  /// The NOTAM's identifier (``NOTAMResponse/notamId``).
  public let notamID: String

  /// A deterministic parser or the on-device model.
  public let reader: NOTAMExtractor.Source

  // MARK: - Initializers

  /// - Parameters:
  ///   - notamID: The NOTAM's identifier.
  ///   - reader: What read it.
  public init(notamID: String, reader: NOTAMExtractor.Source) {
    self.notamID = notamID
    self.reader = reader
  }
}

extension Array {
  fileprivate mutating func merge<Value>(_ others: [Candidate<Value>])
  where Element == Candidate<Value> {
    for other in others {
      if let index = firstIndex(where: { $0.value == other.value }) {
        self[index].add(other.sources)
      } else {
        append(other)
      }
    }
  }
}
