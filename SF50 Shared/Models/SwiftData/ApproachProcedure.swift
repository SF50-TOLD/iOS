import Foundation
import SwiftData

/// An instrument approach procedure.
///
/// ``ApproachProcedure`` represents an instrument approach procedure from
/// CIFP (Coded Instrument Flight Procedures) data. It includes the procedure
/// identifier, full human-readable name, and missed approach fixes with
/// altitude constraints (when the missed approach is plottable).
@Model
public final class ApproachProcedure {
  #Unique<ApproachProcedure>([\.airport, \.identifier])

  /// CIFP identifier (e.g., "I23LZ", "R28LY") — unique per airport.
  public var identifier: String

  /// Full approach name (e.g., "ILS Z RWY 23L", "RNAV Y RWY 28L").
  public var name: String

  /// The airport this procedure belongs to
  @Relationship(deleteRule: .nullify, inverse: \Airport.approachProcedures)
  public var airport: Airport?

  /// Missed approach legs with altitude constraints
  @Relationship(deleteRule: .cascade)
  public var missedApproachLegs: [Leg]

  /// Whether the missed approach has plottable legs with altitude constraints.
  public var isMissedApproachPlottable: Bool {
    !missedApproachLegs.isEmpty
  }

  /// Creates a new approach procedure.
  ///
  /// - Parameters:
  ///   - identifier: CIFP procedure identifier.
  ///   - name: Full human-readable approach name.
  ///   - airport: The airport this procedure belongs to.
  public init(
    identifier: String,
    name: String,
    airport: Airport? = nil
  ) {
    self.identifier = identifier
    self.name = name
    self.airport = airport
    self.missedApproachLegs = []
  }
}
