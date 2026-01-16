import Foundation
import SwiftCIFP
import SwiftDOF
import SwiftNASR

/// Codable container for the airport database distributed with the app.
///
/// ``AirportDataCodable`` represents the entire airport database in a format
/// suitable for encoding to property list and LZMA compression. It combines
/// data from FAA NASR and OurAirports sources.
///
/// ## Data Sources
///
/// The database merges two sources with NASR taking priority:
/// - **NASR**: FAA National Airspace System Resources (US airports)
/// - **OurAirports**: Community database (international airports)
///
/// ## File Format
///
/// The data is serialized to binary property list format, then LZMA-compressed
/// for distribution. Files are named by AIRAC cycle (e.g., `2501.plist.lzma`).
///
/// ## See Also
///
/// - ``AirportCodable``
/// - ``RunwayCodable``
public struct AirportDataCodable: Codable, Sendable {
  /// NASR AIRAC cycle identifier (e.g., 2501 for January 2025)
  public let nasrCycle: SwiftNASR.Cycle?

  /// CIFP AIRAC cycle identifier
  public let cifpCycle: SwiftCIFP.Cycle?

  /// DOF (Digital Obstacle File) cycle identifier
  public let dofCycle: DOFCycleCodable?

  /// Date when OurAirports data was last updated
  public let ourAirportsLastUpdated: Date?

  /// All airports in the database
  public let airports: [AirportCodable]

  /// All obstacles in the database (from FAA Digital Obstacle File)
  public let obstacles: [ObstacleCodable]

  /**
   * Codable representation of an airport.
   *
   * ``AirportCodable`` stores airport data in a format optimized for
   * serialization and storage. All measurements use metric units (meters, degrees).
   */
  public struct AirportCodable: Codable, Sendable {
    /// Unique database record identifier
    public let recordID: String

    /// FAA location identifier (e.g., "SFO")
    public let locationID: String

    /// ICAO identifier if available (e.g., "KSFO")
    public let ICAO_ID: String?

    /// Airport name
    public let name: String

    /// City or municipality
    public let city: String?

    /// Data source: "nasr" or "ourAirports"
    public let dataSource: String

    /// Latitude in decimal degrees
    public let latitude: Double

    /// Longitude in decimal degrees
    public let longitude: Double

    /// Field elevation in meters
    public let elevation: Double

    /// Magnetic variation in degrees (positive = east)
    public let variation: Double

    /// IANA timezone identifier (e.g., "America/Los_Angeles")
    public let timeZone: String?

    /// Runways at this airport
    public let runways: [RunwayCodable]

    /// Departure procedures (SIDs) at this airport (nil if CIFP data not available)
    public let departureProcedures: [DepartureProcedureCodable]?
  }

  /**
   * Codable representation of a runway.
   *
   * ``RunwayCodable`` stores runway data in metric units for serialization.
   * Each physical runway is represented as two separate entries (one per direction).
   */
  public struct RunwayCodable: Codable, Sendable {
    /// Runway designator (e.g., "28L")
    public let name: String

    /// Threshold elevation in meters (nil if not available)
    public let elevation: Double?

    /// True heading in degrees
    public let trueHeading: Double

    /// Gradient as a fraction (positive = uphill)
    public let gradient: Float?

    /// Total runway length in meters
    public let length: Double

    /// Takeoff run available (TORA) in meters
    public let takeoffRun: Double?

    /// Takeoff distance available (TODA) in meters
    public let takeoffDistance: Double?

    /// Landing distance available (LDA) in meters
    public let landingDistance: Double?

    /// Whether the runway has a turf (grass) surface
    public let isTurf: Bool

    /// Name of the reciprocal runway (e.g., "10R" for runway "28L")
    public let reciprocalName: String?

    /// Threshold latitude in decimal degrees (nil if not available)
    public let thresholdLatitude: Double?

    /// Threshold longitude in decimal degrees (nil if not available)
    public let thresholdLongitude: Double?

    /// Runway width in meters (nil if not available)
    public let width: Double?

    /// Threshold crossing height in meters AGL (nil if not available)
    public let thresholdCrossingHeight: Double?

    /// Glidepath angle in degrees from ILS glideslope or visual approach indicator (nil if not available)
    public let glidepathAngle: Double?

    /// Displaced threshold distance from runway end in meters (nil if threshold is at runway end)
    public let displacedThresholdDistance: Double?
  }

  /**
   * Codable representation of a departure procedure (SID).
   *
   * ``DepartureProcedureCodable`` stores departure procedure data extracted from CIFP.
   * For plottable SIDs (those with deterministic path terminators), fixes are included
   * with their coordinates and altitude constraints.
   */
  public struct DepartureProcedureCodable: Codable, Sendable {
    /// Procedure identifier (e.g., "RNAV1", "WLSON7")
    public let identifier: String

    /// Associated runway designators (e.g., ["28L", "28R"])
    public let runwayNames: [String]

    /// Fixes along the procedure (nil if not plottable)
    public let fixes: [FixCodable]?

    /// Required climb gradient in feet per nautical mile (nil if not plottable or no altitude constraints)
    public let requiredClimbGradientFtPerNM: Double?
  }

  /**
   * Codable representation of a fix/waypoint in a procedure.
   */
  public struct FixCodable: Codable, Sendable {
    /// Fix identifier (e.g., "PORTE", "WLSON")
    public let identifier: String

    /// Latitude in decimal degrees
    public let latitude: Double

    /// Longitude in decimal degrees
    public let longitude: Double

    /// Altitude restriction (nil if no restriction)
    public let altitudeRestriction: AltitudeRestrictionCodable?
  }

  /**
   * Codable representation of an altitude restriction.
   *
   * Encodes as simple key-value pairs:
   * - `{at: 1300}`
   * - `{atOrAbove: 1300}`
   * - `{atOrBelow: 1300}`
   * - `{between: [1200, 1300]}`
   */
  public enum AltitudeRestrictionCodable: Codable, Sendable, Equatable {
    case at(Int)
    case atOrAbove(Int)
    case atOrBelow(Int)
    case between(min: Int, max: Int)

    public init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)

      if let value = try container.decodeIfPresent(Int.self, forKey: .at) {
        self = .at(value)
      } else if let value = try container.decodeIfPresent(Int.self, forKey: .atOrAbove) {
        self = .atOrAbove(value)
      } else if let value = try container.decodeIfPresent(Int.self, forKey: .atOrBelow) {
        self = .atOrBelow(value)
      } else if let values = try container.decodeIfPresent([Int].self, forKey: .between),
        values.count == 2
      {
        self = .between(min: values[0], max: values[1])
      } else {
        throw DecodingError.dataCorrupted(
          DecodingError.Context(
            codingPath: decoder.codingPath,
            debugDescription: "Unable to decode AltitudeRestrictionCodable"
          )
        )
      }
    }

    public func encode(to encoder: Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)

      switch self {
        case .at(let value):
          try container.encode(value, forKey: .at)
        case .atOrAbove(let value):
          try container.encode(value, forKey: .atOrAbove)
        case .atOrBelow(let value):
          try container.encode(value, forKey: .atOrBelow)
        case .between(let min, let max):
          try container.encode([min, max], forKey: .between)
      }
    }

    private enum CodingKeys: String, CodingKey {
      case at, atOrAbove, atOrBelow, between
    }
  }

  /**
   * Codable representation of a DOF cycle.
   *
   * This wrapper ensures the cycle encodes as a dictionary with year/month/day
   * rather than as a raw string value.
   */
  public struct DOFCycleCodable: Codable, Sendable {
    /// The year of the cycle
    public let year: UInt

    /// The month of the cycle
    public let month: UInt8

    /// The day of the cycle
    public let day: UInt8

    /// Creates a DOFCycleCodable from a SwiftDOF.Cycle
    public init(_ cycle: SwiftDOF.Cycle) {
      self.year = cycle.year
      self.month = cycle.month
      self.day = cycle.day
    }
  }

  /**
   * Codable representation of an obstacle.
   *
   * ``ObstacleCodable`` stores obstacle data extracted from the FAA Digital Obstacle File.
   * Only the fields needed for departure obstacle analysis are included to minimize file size.
   */
  public struct ObstacleCodable: Codable, Sendable {
    /// Height above mean sea level in feet
    public let heightFtMSL: Int

    /// Latitude in decimal degrees
    public let latitude: Double

    /// Longitude in decimal degrees
    public let longitude: Double
  }
}
