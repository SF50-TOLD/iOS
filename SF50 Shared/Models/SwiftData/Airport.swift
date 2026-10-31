public import CoreLocation
public import Foundation
public import NavData
public import SwiftData

/// An airport with associated runways and location data.
///
/// ``Airport`` represents an aerodrome with its associated metadata including
/// location, elevation, magnetic variation, and runways. Airport data is
/// persisted using SwiftData and resolved from every source that describes it (see
/// ``sources``).
@Model
public final class Airport {
  /// Composite index accelerating nearest-airport bounding-box queries on latitude/longitude.
  #Index<Airport>([\._latitude, \._longitude])

  /// Unique, stable identifier, such as `FAA:04508.*A` or `ICAO:EDDM`
  @Attribute(.unique)
  public var recordID: String

  /// Airport identifier (e.g., KJFK, KSFO)
  public var locationID: String

  /// ICAO identifier if available
  public var ICAO_ID: String?

  /// Airport name
  public var name: String

  /// City where airport is located
  public var city: String?

  /// ISO 3166-1 alpha-2 country code, if known
  public var countryCode: String?

  var _sources: [String]  // AirportDataSource raw values, highest priority first

  var _latitude: Double  // decimal degrees
  var _longitude: Double  // decimal degrees
  var _elevation: Double  // meters
  var _variation: Double  // degrees
  var _timeZone: String?  // IANA timezone identifier (e.g., "America/Los_Angeles")

  /// Runways associated with this airport
  @Relationship(deleteRule: .cascade)
  public var runways: [Runway]

  /// All procedures (departures and approaches) available at this airport
  @Relationship(deleteRule: .cascade)
  public var procedures: [Procedure]

  /// The identifiers this airport has had or is known by besides ``recordID``
  @Relationship(deleteRule: .cascade, inverse: \AirportAlias.airport)
  public var aliases: [AirportAlias]

  /// The sources that contributed to this airport, highest priority first
  public var sources: [AirportDataSource] {
    get { _sources.map(AirportDataSource.init) }
    set { _sources = newValue.map(\.rawValue) }
  }

  /// Departure procedures available at this airport
  public var departureProcedures: [Procedure] {
    procedures.filter { $0.type == .departure }
  }

  /// Approach procedures available at this airport
  public var approachProcedures: [Procedure] {
    procedures.filter { $0.type == .approach }
  }

  /// Airport latitude in degrees
  public var latitude: Measurement<UnitAngle> {
    get { .init(value: _latitude, unit: .degrees) }
    set { _latitude = newValue.converted(to: .degrees).value }
  }

  /// Airport longitude in degrees
  public var longitude: Measurement<UnitAngle> {
    get { .init(value: _longitude, unit: .degrees) }
    set { _longitude = newValue.converted(to: .degrees).value }
  }

  /// Airport elevation above sea level
  public var elevation: Measurement<UnitLength> {
    get { .init(value: _elevation, unit: .meters) }
    set { _elevation = newValue.converted(to: .meters).value }
  }

  /// Magnetic variation at the airport location
  public var variation: Measurement<UnitAngle> {
    get { .init(value: _variation, unit: .degrees) }
    set { _variation = newValue.converted(to: .degrees).value }
  }

  /// Airport timezone
  public var timeZone: TimeZone? {
    get {
      guard let _timeZone else { return nil }
      return TimeZone(identifier: _timeZone)
    }
    set { _timeZone = newValue?.identifier }
  }

  /// CoreLocation coordinate for the airport
  public var coordinate: CLLocationCoordinate2D {
    .init(
      latitude: latitude.converted(to: .degrees).value,
      longitude: longitude.converted(to: .degrees).value
    )
  }

  /// CoreLocation location object for the airport
  public var location: CLLocation {
    .init(
      latitude: latitude.converted(to: .degrees).value,
      longitude: longitude.converted(to: .degrees).value
    )
  }

  /// Display identifier: the FAA identifier for NASR airports, otherwise the ICAO identifier
  /// where there is one
  public var displayID: String {
    if sources.first == .NASR {
      return locationID
    }
    return ICAO_ID ?? locationID
  }

  /**
   * Creates a new airport.
   *
   * - Parameters:
   *   - recordID: Unique identifier for SwiftData persistence.
   *   - locationID: FAA location identifier (e.g., "JFK", "SFO").
   *   - ICAO_ID: ICAO identifier if available (e.g., "KJFK").
   *   - name: Full airport name.
   *   - city: City where the airport is located.
   *   - sources: The sources that contributed, highest priority first.
   *   - countryCode: ISO 3166-1 alpha-2 country code, if known.
   *   - latitude: Airport latitude.
   *   - longitude: Airport longitude.
   *   - elevation: Field elevation above sea level.
   *   - variation: Magnetic variation (positive = east).
   *   - timeZone: Local timezone for the airport.
   */
  public init(
    recordID: String,
    locationID: String,
    ICAO_ID: String?,
    name: String,
    city: String?,
    sources: [AirportDataSource],
    countryCode: String? = nil,
    latitude: Measurement<UnitAngle>,
    longitude: Measurement<UnitAngle>,
    elevation: Measurement<UnitLength>,
    variation: Measurement<UnitAngle>,
    timeZone: TimeZone? = nil
  ) {
    self.recordID = recordID
    self.locationID = locationID
    self.ICAO_ID = ICAO_ID
    self.name = name
    self.city = city
    _sources = sources.map(\.rawValue)
    self.countryCode = countryCode
    _latitude = latitude.converted(to: .degrees).value
    _longitude = longitude.converted(to: .degrees).value
    _elevation = elevation.converted(to: .meters).value
    _variation = variation.converted(to: .degrees).value
    _timeZone = timeZone?.identifier
    self.runways = []
    self.procedures = []
    self.aliases = []
  }
}
