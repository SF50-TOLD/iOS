import Foundation
import SwiftData

/// A departure procedure (SID, ODP, or obstacle departure procedure).
///
/// ``DepartureProcedure`` represents an instrument departure procedure from
/// CIFP (Coded Instrument Flight Procedures) data. It includes the procedure
/// identifier, associated runways, required climb gradient if any, and the
/// sequence of fixes that define the procedure route.
///
/// ## Topics
///
/// ### Identification
/// - ``identifier``
/// - ``runwayNames``
///
/// ### Requirements
/// - ``requiredClimbGradientFtPerNM``
///
/// ### Route
/// - ``fixes``
/// - ``isPlottable``
///
/// ### Relationships
/// - ``airport``
@Model
public final class DepartureProcedure {
  #Unique<DepartureProcedure>([\.airport, \.identifier])

  /// Procedure identifier (e.g., "ORCKA2", "REBAS1")
  public var identifier: String

  /// Runway names this procedure applies to (e.g., ["28L", "28R"])
  ///
  /// Stored as strings rather than relationships because runways may not exist
  /// when procedures are loaded.
  public var runwayNames: [String]

  /// Required climb gradient in feet per nautical mile, if specified
  private var _requiredClimbGradient: Double?

  /// The airport this procedure belongs to
  @Relationship(deleteRule: .nullify, inverse: \Airport.departureProcedures)
  public var airport: Airport?

  /// Fixes that define the procedure route
  @Relationship(deleteRule: .cascade)
  public var fixes: [Fix]

  /// Required climb gradient in feet per nautical mile
  ///
  /// Standard climb gradient is 200 ft/NM. Values above this indicate
  /// obstacle clearance requirements.
  public var requiredClimbGradientFtPerNM: Double? {
    get { _requiredClimbGradient }
    set { _requiredClimbGradient = newValue }
  }

  /// Whether this procedure has fixes that can be plotted on a map
  public var isPlottable: Bool {
    !fixes.isEmpty
  }

  /// Creates a new departure procedure.
  ///
  /// - Parameters:
  ///   - identifier: Procedure identifier.
  ///   - runwayNames: Runway names this procedure applies to.
  ///   - requiredClimbGradientFtPerNM: Required climb gradient in ft/NM, if any.
  ///   - airport: The airport this procedure belongs to.
  public init(
    identifier: String,
    runwayNames: [String] = [],
    requiredClimbGradientFtPerNM: Double? = nil,
    airport: Airport? = nil
  ) {
    self.identifier = identifier
    self.runwayNames = runwayNames
    _requiredClimbGradient = requiredClimbGradientFtPerNM
    self.airport = airport
    self.fixes = []
  }
}
