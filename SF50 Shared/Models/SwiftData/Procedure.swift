import Foundation
public import SwiftData

/// A unified instrument procedure (departure SID or approach).
///
/// ``Procedure`` represents either a departure procedure (SID) or an approach
/// procedure from CIFP data. Each procedure contains one or more ``ProcedureSegment``
/// objects: runway transitions (runway-specific initial legs) and a common route
/// (shared by all runways), or a missed approach segment (for approaches).
@Model
public final class Procedure {
  #Unique<Procedure>([\.airport, \._type, \.identifier])

  private var _type: String

  /// Procedure identifier (e.g., "LINDZ1", "I23LZ")
  public var identifier: String

  /// Human-readable name (approaches only, e.g., "ILS Z RWY 23L")
  public var name: String?

  /// Associated runway designator for approaches (e.g., "28L")
  public var runwayName: String?

  private var _requiredClimbGradient: Double?

  /// The airport this procedure belongs to
  @Relationship(deleteRule: .nullify, inverse: \Airport.procedures)
  public var airport: Airport?

  /// Segments that compose this procedure (runway transitions, common route, missed approach)
  @Relationship(deleteRule: .cascade)
  public var segments: [ProcedureSegment]

  /// The procedure type (departure or approach).
  public var type: ProcedureType { .init(rawValue: _type)! }

  // periphery:ignore - facade over private SwiftData storage; part of the model schema API
  /// Required climb gradient in feet per nautical mile (departures only).
  ///
  /// Standard climb gradient is 200 ft/NM. Values above this indicate
  /// obstacle clearance requirements.
  public var requiredClimbGradientFtPerNM: Double? {
    get { _requiredClimbGradient }
    set { _requiredClimbGradient = newValue }
  }

  /// Runway names derived from runway-transition segments (departures).
  public var runwayNames: [String] {
    Array(Set(segments.filter { !$0.runwayNames.isEmpty }.flatMap(\.runwayNames))).sorted()
  }

  /// Whether the missed approach segment has plottable legs (approaches only).
  public var isMissedApproachPlottable: Bool {
    // Missed approach legs are stored in a segment with empty runwayNames
    let missedLegs =
      segments
      .first(where: \.runwayNames.isEmpty)?
      .legs ?? []
    guard !missedLegs.isEmpty else { return false }
    let sorted = missedLegs.sorted { $0.sequenceIndex < $1.sequenceIndex }
    return sorted.enumerated().allSatisfy { index, leg in
      leg.legType.isPlottable
        && (!leg.legType.isTerminalOnly || index == sorted.count - 1)
        && leg.hasRequiredData
    }
  }

  /// Missed approach legs in execution order (approaches only).
  public var missedApproachLegs: [Leg] {
    segments
      .first(where: \.runwayNames.isEmpty)?
      .legs.sorted { $0.sequenceIndex < $1.sequenceIndex } ?? []
  }

  /// Creates a new procedure.
  ///
  /// - Parameters:
  ///   - type: Whether this is a departure or approach procedure.
  ///   - identifier: Procedure identifier.
  ///   - name: Human-readable name (approaches only).
  ///   - runwayName: Associated runway designator (approaches only).
  ///   - requiredClimbGradientFtPerNM: Required climb gradient in ft/NM (departures only).
  ///   - airport: The airport this procedure belongs to.
  public init(
    type: ProcedureType,
    identifier: String,
    name: String? = nil,
    runwayName: String? = nil,
    requiredClimbGradientFtPerNM: Double? = nil,
    airport: Airport? = nil
  ) {
    _type = type.rawValue
    self.identifier = identifier
    self.name = name
    self.runwayName = runwayName
    _requiredClimbGradient = requiredClimbGradientFtPerNM
    self.airport = airport
    self.segments = []
  }

  /// Compose legs for path generation: runway transition (if any) + common route, in order.
  public func composedLegs(forRunway runway: String) -> [Leg] {
    let rwLegs =
      segments
      .first { $0.runwayNames.contains(runway) }?
      .legs.sorted { $0.sequenceIndex < $1.sequenceIndex } ?? []
    let commonLegs =
      segments
      .first(where: \.runwayNames.isEmpty)?
      .legs.sorted { $0.sequenceIndex < $1.sequenceIndex } ?? []
    return rwLegs + commonLegs
  }

  /// Whether this procedure has legs that can be plotted on a map for the given runway.
  public func isPlottable(forRunway runway: String) -> Bool {
    let legs = composedLegs(forRunway: runway)
    guard !legs.isEmpty else { return false }

    // Check for vectoring gaps: a non-intercept heading leg followed by
    // courseToFix means ATC must vector the aircraft onto the course.
    for i in 0..<(legs.count - 1) {
      if legs[i].legType.isNonInterceptHeading && legs[i + 1].legType.isCourseToFix {
        return false
      }
    }

    return legs.enumerated().allSatisfy { index, leg in
      leg.legType.isPlottable
        && (!leg.legType.isTerminalOnly || index == legs.count - 1)
        && leg.hasRequiredData
    }
  }

  public enum ProcedureType: String, Codable, Sendable {
    case departure
    case approach
  }
}
