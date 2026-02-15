import Foundation
import SwiftData

/// A segment within an instrument procedure.
///
/// ``ProcedureSegment`` groups legs that belong to the same logical part of a
/// procedure. For departures, a segment with non-empty ``runwayNames`` is a
/// runway transition (runway-specific initial climb); a segment with empty
/// ``runwayNames`` is the common route shared by all runways. For approaches,
/// the segment with empty ``runwayNames`` contains the missed approach legs.
@Model
public final class ProcedureSegment {
  /// Runways this segment applies to. Non-empty = runway transition; empty = common route / missed approach.
  public var runwayNames: [String]

  /// Legs that define this segment's route
  @Relationship(deleteRule: .cascade)
  public var legs: [Leg]

  /// The procedure this segment belongs to
  @Relationship(deleteRule: .nullify, inverse: \Procedure.segments)
  public var procedure: Procedure?

  /// Creates a new procedure segment.
  ///
  /// - Parameters:
  ///   - runwayNames: Runway names this segment applies to (empty for common route / missed approach).
  ///   - procedure: The procedure this segment belongs to.
  public init(
    runwayNames: [String] = [],
    procedure: Procedure? = nil
  ) {
    self.runwayNames = runwayNames
    self.procedure = procedure
    self.legs = []
  }
}
