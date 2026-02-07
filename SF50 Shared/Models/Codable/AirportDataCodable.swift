import Foundation

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
  /// Data source cycle information with effective and expiration dates.
  public let cycles: DataCycles

  /// Date when OurAirports data was last updated
  public let ourAirportsLastUpdated: Date?

  /// All airports in the database
  public let airports: [AirportCodable]

  /// All obstacles in the database (from FAA Digital Obstacle File)
  public let obstacles: [ObstacleCodable]

  /// DME-capable navaids referenced by procedure legs (nil for older data files)
  public let navaids: [NavaidCodable]?

  public init(
    cycles: DataCycles,
    ourAirportsLastUpdated: Date?,
    airports: [AirportCodable],
    obstacles: [ObstacleCodable],
    navaids: [NavaidCodable]? = nil
  ) {
    self.cycles = cycles
    self.ourAirportsLastUpdated = ourAirportsLastUpdated
    self.airports = airports
    self.obstacles = obstacles
    self.navaids = navaids
  }

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

    /// Approach procedures at this airport (nil if CIFP data not available)
    public let approachProcedures: [ApproachProcedureCodable]?

    public init(
      recordID: String,
      locationID: String,
      ICAO_ID: String?,
      name: String,
      city: String?,
      dataSource: String,
      latitude: Double,
      longitude: Double,
      elevation: Double,
      variation: Double,
      timeZone: String?,
      runways: [RunwayCodable],
      departureProcedures: [DepartureProcedureCodable]?,
      approachProcedures: [ApproachProcedureCodable]?
    ) {
      self.recordID = recordID
      self.locationID = locationID
      self.ICAO_ID = ICAO_ID
      self.name = name
      self.city = city
      self.dataSource = dataSource
      self.latitude = latitude
      self.longitude = longitude
      self.elevation = elevation
      self.variation = variation
      self.timeZone = timeZone
      self.runways = runways
      self.departureProcedures = departureProcedures
      self.approachProcedures = approachProcedures
    }
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

    public init(
      name: String,
      elevation: Double?,
      trueHeading: Double,
      gradient: Float?,
      length: Double,
      takeoffRun: Double?,
      takeoffDistance: Double?,
      landingDistance: Double?,
      isTurf: Bool,
      reciprocalName: String?,
      thresholdLatitude: Double?,
      thresholdLongitude: Double?,
      width: Double?,
      thresholdCrossingHeight: Double?,
      glidepathAngle: Double?,
      displacedThresholdDistance: Double?
    ) {
      self.name = name
      self.elevation = elevation
      self.trueHeading = trueHeading
      self.gradient = gradient
      self.length = length
      self.takeoffRun = takeoffRun
      self.takeoffDistance = takeoffDistance
      self.landingDistance = landingDistance
      self.isTurf = isTurf
      self.reciprocalName = reciprocalName
      self.thresholdLatitude = thresholdLatitude
      self.thresholdLongitude = thresholdLongitude
      self.width = width
      self.thresholdCrossingHeight = thresholdCrossingHeight
      self.glidepathAngle = glidepathAngle
      self.displacedThresholdDistance = displacedThresholdDistance
    }
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

    /// Legs along the procedure (nil if not plottable)
    public let legs: [LegCodable]?

    /// Required climb gradient in feet per nautical mile (nil if not plottable or no altitude constraints)
    public let requiredClimbGradientFtPerNM: Double?

    public init(
      identifier: String,
      runwayNames: [String],
      legs: [LegCodable]?,
      requiredClimbGradientFtPerNM: Double?
    ) {
      self.identifier = identifier
      self.runwayNames = runwayNames
      self.legs = legs
      self.requiredClimbGradientFtPerNM = requiredClimbGradientFtPerNM
    }
  }

  /**
   * Codable representation of an approach procedure.
   *
   * ``ApproachProcedureCodable`` stores approach procedure data extracted from CIFP.
   * For approaches with plottable missed approach legs, fixes with altitude constraints
   * are included.
   */
  public struct ApproachProcedureCodable: Codable, Sendable {
    /// CIFP identifier (e.g., "I23LZ")
    public let identifier: String

    /// Full approach name (e.g., "ILS Z RWY 23L")
    public let name: String

    /// Missed approach legs with altitude constraints (nil if missed approach not plottable)
    public let missedApproachLegs: [LegCodable]?

    public init(
      identifier: String,
      name: String,
      missedApproachLegs: [LegCodable]?
    ) {
      self.identifier = identifier
      self.name = name
      self.missedApproachLegs = missedApproachLegs
    }
  }

  /**
   * Codable representation of a procedure leg.
   */
  public struct LegCodable: Codable, Sendable {
    /// Fix identifier (e.g., "PORTE", "WLSON"). Nil for *ToAltitude legs with no fix.
    public let identifier: String?

    /// Latitude in decimal degrees. Nil for legs with no fix (e.g., CA/VA).
    public let latitude: Double?

    /// Longitude in decimal degrees. Nil for legs with no fix (e.g., CA/VA).
    public let longitude: Double?

    /// Altitude restriction (nil if no restriction)
    public let altitudeRestriction: AltitudeRestrictionCodable?

    /// Leg type geometry for plotting
    public let legType: LegTypeCodable

    /// Recommended navaid identifier for DME legs (nil if not a DME leg)
    public let recommendedNavaidIdentifier: String?

    /// ICAO region of the recommended navaid (nil if not a DME leg)
    public let recommendedNavaidICAO: String?

    /// DME termination distance in nautical miles (nil if not a DME leg)
    public let dmeDistanceNM: Double?

    public init(
      identifier: String?,
      latitude: Double?,
      longitude: Double?,
      altitudeRestriction: AltitudeRestrictionCodable?,
      legType: LegTypeCodable,
      recommendedNavaidIdentifier: String? = nil,
      recommendedNavaidICAO: String? = nil,
      dmeDistanceNM: Double? = nil
    ) {
      self.identifier = identifier
      self.latitude = latitude
      self.longitude = longitude
      self.altitudeRestriction = altitudeRestriction
      self.legType = legType
      self.recommendedNavaidIdentifier = recommendedNavaidIdentifier
      self.recommendedNavaidICAO = recommendedNavaidICAO
      self.dmeDistanceNM = dmeDistanceNM
    }
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

  // MARK: - Cycle Information

  /**
   * Container for all data source cycle information.
   *
   * ``DataCycles`` provides structured information about each data source's
   * cycle, including human-readable names and effective/expiration dates.
   */
  public struct DataCycles: Codable, Sendable {
    /// NASR (National Airspace System Resources) cycle information
    public let nasr: CycleInfo?

    /// CIFP (Coded Instrument Flight Procedures) cycle information
    public let cifp: CycleInfo?

    /// DOF (Digital Obstacle File) cycle information
    public let dof: CycleInfo?

    public init(nasr: CycleInfo?, cifp: CycleInfo?, dof: CycleInfo?) {
      self.nasr = nasr
      self.cifp = cifp
      self.dof = dof
    }
  }

  /**
   * Information about a single data source cycle.
   *
   * ``CycleInfo`` contains all the information needed to display cycle
   * information to users and determine if the data is still current.
   */
  public struct CycleInfo: Codable, Sendable {
    /// Human-readable cycle identifier (e.g., "2501" for AIRAC cycle)
    public let name: String

    /// Date when this cycle became effective
    public let effective: Date

    /// Date when this cycle expires and should be replaced
    public let expires: Date

    /// Whether this cycle is currently effective (not yet expired)
    public var isEffective: Bool { (effective..<expires).contains(Date()) }

    public init(name: String, effective: Date, expires: Date) {
      self.name = name
      self.effective = effective
      self.expires = expires
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

    public init(heightFtMSL: Int, latitude: Double, longitude: Double) {
      self.heightFtMSL = heightFtMSL
      self.latitude = latitude
      self.longitude = longitude
    }
  }
}
