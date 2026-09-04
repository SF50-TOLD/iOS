public import CoreLocation
public import Foundation
public import SwiftData

/// A DME-capable navigation aid station.
///
/// ``Navaid`` represents a VHF navigation facility with DME capability (VOR/DME,
/// VORTAC, DME, TACAN, ILS/DME, etc.). Procedure legs that terminate at a DME
/// distance reference their station via the ``Leg/navaid`` relationship.
///
/// ## Unique Identity
///
/// Two navaids can share the same short identifier across ICAO regions, so the
/// composite key of ``identifier`` + ``icaoRegion`` uniquely identifies a station.
@Model
public final class Navaid {
  #Unique<Navaid>([\.identifier, \.icaoRegion])

  /// Short identifier (e.g., "OAK", "SFO")
  public var identifier: String

  /// ICAO region code (e.g., "K2")
  public var icaoRegion: String

  /// Facility type description (e.g., "VOR/DME", "VORTAC", "DME", "TACAN")
  public var type: String

  private var _latitude: Double  // decimal degrees (DME transponder position)
  private var _longitude: Double  // decimal degrees
  private var _elevation: Double?  // meters (DME antenna elevation)

  /// DME transponder latitude
  public var latitude: Measurement<UnitAngle> {
    get { .init(value: _latitude, unit: .degrees) }
    set { _latitude = newValue.converted(to: .degrees).value }
  }

  /// DME transponder longitude
  public var longitude: Measurement<UnitAngle> {
    get { .init(value: _longitude, unit: .degrees) }
    set { _longitude = newValue.converted(to: .degrees).value }
  }

  /// CoreLocation coordinate for the DME transponder
  public var coordinate: CLLocationCoordinate2D {
    .init(
      latitude: latitude.converted(to: .degrees).value,
      longitude: longitude.converted(to: .degrees).value
    )
  }

  /// DME antenna elevation (nil if not available)
  public var elevation: Measurement<UnitLength>? {
    get { _elevation.map { .init(value: $0, unit: .meters) } }
    set { _elevation = newValue?.converted(to: .meters).value }
  }

  /// Legs that reference this navaid for DME distance termination
  @Relationship(deleteRule: .nullify)
  public var legs: [Leg] = []

  /// Creates a new navaid.
  ///
  /// - Parameters:
  ///   - identifier: Short identifier (e.g., "OAK").
  ///   - icaoRegion: ICAO region code (e.g., "K2").
  ///   - type: Facility type description (e.g., "VOR/DME").
  ///   - latitude: DME transponder latitude.
  ///   - longitude: DME transponder longitude.
  ///   - elevation: DME antenna elevation, if available.
  public init(
    identifier: String,
    icaoRegion: String,
    type: String,
    latitude: Measurement<UnitAngle>,
    longitude: Measurement<UnitAngle>,
    elevation: Measurement<UnitLength>? = nil
  ) {
    self.identifier = identifier
    self.icaoRegion = icaoRegion
    self.type = type
    _latitude = latitude.converted(to: .degrees).value
    _longitude = longitude.converted(to: .degrees).value
    _elevation = elevation?.converted(to: .meters).value
  }
}
