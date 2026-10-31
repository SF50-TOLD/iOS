public import SwiftData

/// An identifier an ``Airport`` has had or is known by besides its ``Airport/recordID``.
///
/// Each nav-data cycle keys airports by their most authoritative identifier, which changes when
/// an airport gains a more authoritative one, and differed in data from before airports were
/// keyed this way. Aliases let identifiers stored from an earlier cycle find the same airport.
@Model
public final class AirportAlias {
  /// The identifier, unique across every airport in the dataset
  @Attribute(.unique)
  public var alias: String

  /// The airport this identifier refers to
  public var airport: Airport?

  /**
   * Creates an alias.
   *
   * - Parameters:
   *   - alias: The identifier.
   *   - airport: The airport it refers to.
   */
  public init(alias: String, airport: Airport) {
    self.alias = alias
    self.airport = airport
  }
}
