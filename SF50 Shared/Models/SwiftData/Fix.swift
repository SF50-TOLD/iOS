import CoreLocation
import Foundation
import SwiftData

/// A navigational fix in a departure procedure.
///
/// ``Fix`` represents a waypoint or intersection that aircraft must cross
/// during a departure procedure. Fixes may have altitude restrictions that
/// specify minimum, maximum, or exact crossing altitudes.
///
/// ## Topics
///
/// ### Identification
/// - ``identifier``
/// - ``sequenceIndex``
///
/// ### Location
/// - ``latitude``
/// - ``longitude``
/// - ``coordinate``
///
/// ### Restrictions
/// - ``altitudeRestriction``
///
/// ### Relationships
/// - ``departureProcedure``
@Model
public final class Fix {
  /// Fix identifier (e.g., "ORCKA", "REBAS")
  public var identifier: String

  private var _latitude: Double  // decimal degrees
  private var _longitude: Double  // decimal degrees

  // Altitude restriction stored as type + values (following NOTAM/Contamination pattern)
  private var _altitudeRestrictionType: String?
  private var _altitudeMin: Double?  // meters
  private var _altitudeMax: Double?  // meters (only used for "between")

  /// Position in the departure procedure fix sequence (0-indexed)
  public var sequenceIndex: Int

  /// The departure procedure this fix belongs to
  @Relationship(deleteRule: .nullify, inverse: \DepartureProcedure.fixes)
  public var departureProcedure: DepartureProcedure?

  /// Fix latitude in degrees
  public var latitude: Measurement<UnitAngle> {
    get { .init(value: _latitude, unit: .degrees) }
    set { _latitude = newValue.converted(to: .degrees).value }
  }

  /// Fix longitude in degrees
  public var longitude: Measurement<UnitAngle> {
    get { .init(value: _longitude, unit: .degrees) }
    set { _longitude = newValue.converted(to: .degrees).value }
  }

  /// CoreLocation coordinate for the fix
  public var coordinate: CLLocationCoordinate2D {
    .init(
      latitude: latitude.converted(to: .degrees).value,
      longitude: longitude.converted(to: .degrees).value
    )
  }

  /// Altitude restriction at this fix
  public var altitudeRestriction: AltitudeRestriction? {
    get {
      .init(
        type: _altitudeRestrictionType,
        altitudeMin: _altitudeMin,
        altitudeMax: _altitudeMax
      )
    }
    set {
      _altitudeRestrictionType = newValue?.type
      _altitudeMin = newValue?.altitudeMin
      _altitudeMax = newValue?.altitudeMax
    }
  }

  /// Creates a new fix.
  ///
  /// - Parameters:
  ///   - identifier: Fix identifier.
  ///   - latitude: Fix latitude.
  ///   - longitude: Fix longitude.
  ///   - altitudeRestriction: Altitude restriction at this fix, if any.
  ///   - sequenceIndex: Position in the procedure fix sequence.
  ///   - departureProcedure: The departure procedure this fix belongs to.
  public init(
    identifier: String,
    latitude: Measurement<UnitAngle>,
    longitude: Measurement<UnitAngle>,
    altitudeRestriction: AltitudeRestriction? = nil,
    sequenceIndex: Int,
    departureProcedure: DepartureProcedure? = nil
  ) {
    self.identifier = identifier
    _latitude = latitude.converted(to: .degrees).value
    _longitude = longitude.converted(to: .degrees).value
    _altitudeRestrictionType = altitudeRestriction?.type
    _altitudeMin = altitudeRestriction?.altitudeMin
    _altitudeMax = altitudeRestriction?.altitudeMax
    self.sequenceIndex = sequenceIndex
    self.departureProcedure = departureProcedure
  }
}
