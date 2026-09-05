import AppIntents
import Foundation
import MeasurementKit
import SF50_Shared
import SwiftData

/// A runway, as Shortcuts and Siri see it.
///
/// `Runway` has no unique column of its own — SwiftData identifies one by the pair of its airport and
/// its name — so this entity's identifier is that pair, joined by a slash. Runway designators never
/// contain one.
///
/// The performance properties are populated only on the runway ``RunwayNumbersIntent`` returns; a
/// runway resolved for a parameter picker carries identity alone. A property is also `nil` when the
/// calculation refused to produce a number, in which case the intent's snippet says why.
struct RunwayEntity: AppEntity {
  static var typeDisplayRepresentation: TypeDisplayRepresentation { "Runway" }

  static var defaultQuery: RunwayEntityQuery { .init() }

  /// The airport's record ID and the runway name, joined by a slash.
  let id: String

  /// The record ID of the airport this runway belongs to.
  let airportRecordID: String

  /// The runway designator, such as "28L".
  let name: String

  /// The identifier the app shows for the airport.
  let airportDisplayID: String

  /// Ground run: brake release to liftoff, or touchdown to full stop.
  @Property(title: "Ground Run")
  var groundRun: Measurement<UnitLength>?

  /// Total distance over the takeoff screen height, or from the landing screen height.
  @Property(title: "Total Distance")
  var distance: Measurement<UnitLength>?

  /// The distance available on this runway for the leg calculated.
  @Property(title: "Available Distance")
  var availableDistance: Measurement<UnitLength>?

  /// Climb gradient at Vx, in feet per nautical mile. Takeoff only.
  @Property(title: "Vx Climb Gradient")
  var climbGradientFtNM: Double?

  /// Reference approach speed. Landing only.
  @Property(title: "VREF")
  var VREF: Measurement<UnitSpeed>?

  /// The headwind component; negative is a tailwind.
  @Property(title: "Headwind")
  var headwind: Measurement<UnitSpeed>?

  /// The crosswind component.
  @Property(title: "Crosswind")
  var crosswind: Measurement<UnitSpeed>?

  /// Why there is no distance, when there is none — `nil` when the numbers are present.
  @Property(title: "Status")
  var status: String?

  var displayRepresentation: DisplayRepresentation {
    .init(title: "\(airportDisplayID) \(name)")
  }

  /// Creates an identity-only entity.
  ///
  /// - Parameters:
  ///   - airportRecordID: The owning airport's record ID.
  ///   - airportDisplayID: The identifier the app shows for the airport.
  ///   - name: The runway designator.
  init(airportRecordID: String, airportDisplayID: String, name: String) {
    id = Self.identifier(airportRecordID: airportRecordID, name: name)
    self.airportRecordID = airportRecordID
    self.airportDisplayID = airportDisplayID
    self.name = name
  }

  /// Joins an airport record ID and a runway name into an entity identifier.
  ///
  /// - Parameters:
  ///   - airportRecordID: The owning airport's record ID.
  ///   - name: The runway designator.
  /// - Returns: The composite identifier.
  static func identifier(airportRecordID: String, name: String) -> String {
    "\(airportRecordID)/\(name)"
  }

  /// Splits a composite identifier back into its two halves.
  ///
  /// - Parameter identifier: An identifier produced by ``identifier(airportRecordID:name:)``.
  /// - Returns: The airport record ID and runway name, or `nil` if the identifier is malformed.
  static func components(of identifier: String) -> (airportRecordID: String, name: String)? {
    guard let separator = identifier.lastIndex(of: "/") else { return nil }
    let airportRecordID = String(identifier[identifier.startIndex..<separator]),
      name = String(identifier[identifier.index(after: separator)...])
    guard !airportRecordID.isEmpty, !name.isEmpty else { return nil }
    return (airportRecordID, name)
  }
}
