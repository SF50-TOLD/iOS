import Foundation
import Logging
import SF50_Shared
import TabularData

/// Downloads and parses airport data from the OurAirports database.
///
/// ``OurAirportsLoader`` fetches CSV data from OurAirports (a community-maintained
/// database) to supplement FAA NASR data with international airports.
///
/// ## Data Source
///
/// CSV files are hosted at `davidmegginson.github.io/ourairports-data/`:
/// - `airports.csv`: Airport records
/// - `runways.csv`: Runway records
///
/// ## Processing
///
/// The loader:
/// 1. Downloads both CSV files
/// 2. Parses using TabularData framework
/// 3. Filters to small/medium/large airports (excludes heliports, seaplane bases)
/// 4. Filters runways ≥500 feet (excludes water runways)
/// 5. Returns ``OurAirportData`` structs
///
/// ## See Also
///
/// - ``OurAirportData``
/// - ``OurRunwayData``
struct OurAirportsLoader {
  private static let airportsURL = URL(
    string: "https://davidmegginson.github.io/ourairports-data/airports.csv"
  )!
  private static let runwaysURL = URL(
    string: "https://davidmegginson.github.io/ourairports-data/runways.csv"
  )!

  private let logger: Logger

  init(logger: Logger) {
    self.logger = logger
  }

  // MARK: - Type Methods

  /// Parses airports and runways data from CSV bytes.
  private static func parseAirports(
    airportsData: Data,
    runwaysData: Data
  ) throws -> [OurAirportData] {
    // Parse airports CSV
    let airportsDataFrame = try DataFrame(
      csvData: airportsData,
      options: CSVReadingOptions(hasHeaderRow: true)
    )

    // Parse runways CSV
    let runwaysDataFrame = try DataFrame(
      csvData: runwaysData,
      options: CSVReadingOptions(hasHeaderRow: true)
    )

    // Convert to our data structures
    var airports = [OurAirportData]()
    let runwaysByAirport = groupRunwaysByAirport(runwaysDataFrame)

    for row in airportsDataFrame.rows {
      guard let id = row["id", Int.self],
        let ident = row["ident", String.self],
        let type = row["type", String.self],
        // Only include airports (not heliports, seaplane bases, etc.)
        ["small_airport", "medium_airport", "large_airport"].contains(type),
        let name = row["name", String.self],
        let latitude = row["latitude_deg", Double.self],
        let longitude = row["longitude_deg", Double.self]
      else {
        continue
      }

      let localId = row["local_code", String.self] ?? ""
      let locationId = localId.isEmpty ? ident : localId
      let ICAO_ID = row["icao_code", String.self]
      let elevation = Double(row["elevation_ft", Int.self] ?? 0)
      let municipality = row["municipality", String.self]

      let runways = runwaysByAirport[ident] ?? []
      let airport = OurAirportData(
        id: String(id),
        localId: locationId,
        ICAO_ID: ICAO_ID,
        name: name,
        municipality: municipality,
        latitude: latitude,
        longitude: longitude,
        elevationFt: elevation,
        runways: runways
      )
      airports.append(airport)
    }

    return airports
  }

  private static func groupRunwaysByAirport(_ runwaysDataFrame: DataFrame) -> [String:
    [OurRunwayData]]
  {
    var runwaysByAirport = [String: [OurRunwayData]]()

    for row in runwaysDataFrame.rows {
      guard let airportIdent = row["airport_ident", String.self],
        let length = row["length_ft", Int.self],
        length >= 500
      else {
        continue
      }

      let surface = row["surface", String.self] ?? ""
      let surfaceType = Self.deriveSurfaceType(surface)

      // Skip water runways
      if surface.lowercased().contains("water") {
        continue
      }

      // Parse width (shared between both ends)
      let widthFt = row["width_ft", Int.self].map { Double($0) }

      // Process low end (base end)
      if let lowIdent = row["le_ident", String.self] {
        let lowElevation = row["le_elevation_ft", Int.self].map { Double($0) }
        let lowHeading = row["le_heading_degT", Double.self] ?? calculateHeadingFromIdent(lowIdent)
        let lowDisplaced = Double(row["le_displaced_threshold_ft", Int.self] ?? 0)
        let lowLatitude = row["le_latitude_deg", Double.self]
        let lowLongitude = row["le_longitude_deg", Double.self]

        let runway = OurRunwayData(
          name: lowIdent,
          elevationFt: lowElevation,
          trueHeading: lowHeading,
          lengthFt: Double(length),
          displacedThresholdFt: lowDisplaced,
          surfaceType: surfaceType,
          reciprocalName: row["he_ident", String.self],
          thresholdLatitude: lowLatitude,
          thresholdLongitude: lowLongitude,
          widthFt: widthFt
        )

        if runwaysByAirport[airportIdent] == nil {
          runwaysByAirport[airportIdent] = []
        }
        runwaysByAirport[airportIdent]?.append(runway)
      }

      // Process high end (reciprocal end)
      if let highIdent = row["he_ident", String.self] {
        let highElevation = row["he_elevation_ft", Int.self].map { Double($0) }
        let highHeading =
          row["he_heading_degT", Double.self] ?? calculateHeadingFromIdent(highIdent)
        let highDisplaced = Double(row["he_displaced_threshold_ft", Int.self] ?? 0)
        let highLatitude = row["he_latitude_deg", Double.self]
        let highLongitude = row["he_longitude_deg", Double.self]

        let runway = OurRunwayData(
          name: highIdent,
          elevationFt: highElevation,
          trueHeading: highHeading,
          lengthFt: Double(length),
          displacedThresholdFt: highDisplaced,
          surfaceType: surfaceType,
          reciprocalName: row["le_ident", String.self],
          thresholdLatitude: highLatitude,
          thresholdLongitude: highLongitude,
          widthFt: widthFt
        )

        if runwaysByAirport[airportIdent] == nil {
          runwaysByAirport[airportIdent] = []
        }
        runwaysByAirport[airportIdent]?.append(runway)
      }
    }

    return runwaysByAirport
  }

  private static func isHardSurface(_ surface: String) -> Bool {
    // Check for hard surface indicators - be inclusive to catch variations
    let hardSurfaceIndicators = ["asp", "conc", "pem", "bit", "tarmac", "paved", "macadam"]
    let lowercased = surface.lowercased()

    // Return true if any hard surface indicator is found
    for indicator in hardSurfaceIndicators where lowercased.contains(indicator) {
      return true
    }

    // CON by itself (not part of "concrete") is also hard surface
    if surface == "CON" { return true }

    return false
  }

  /// Derives ``SurfaceType`` from OurAirports surface description string.
  private static func deriveSurfaceType(_ surface: String) -> SurfaceType {
    guard isHardSurface(surface) else { return .turf }

    let lowercased = surface.lowercased()
    if lowercased.contains("groov") { return .grooved }
    if lowercased.contains("pfc") { return .pfc }
    return .paved
  }

  private static func calculateHeadingFromIdent(_ ident: String) -> Double {
    // Extract numeric part from runway identifier (e.g., "09L" -> 09)
    let digits = ident.prefix(2).filter(\.isNumber)
    guard let runwayNumber = Double(digits) else { return 0 }
    return runwayNumber * 10  // Convert to degrees (09 -> 090)
  }

  // MARK: - Instance Methods

  func loadAirports(
    onProgress: (@Sendable (Int, Int) async -> Void)? = nil
  ) async throws -> ([OurAirportData], Date) {
    logger.notice("Downloading OurAirports data…")
    await onProgress?(0, 2)

    // Download CSV files
    let (airportsData, _) = try await URLSession.shared.data(from: Self.airportsURL)
    let (runwaysData, _) = try await URLSession.shared.data(from: Self.runwaysURL)
    await onProgress?(1, 2)

    logger.notice("Parsing OurAirports CSVs…")

    // Parse and process data on background thread to avoid blocking UI
    // Use static methods to avoid capturing non-Sendable self
    let airports = try await Task.detached {
      try Self.parseAirports(airportsData: airportsData, runwaysData: runwaysData)
    }.value

    // Use current date as last updated
    let lastUpdated = Date()
    await onProgress?(2, 2)

    logger.notice("Loaded \(airports.count) airports from OurAirports")
    return (airports, lastUpdated)
  }
}

/// Airport data parsed from OurAirports CSV.
///
/// Contains airport metadata needed for the app's airport database.
/// Values are in OurAirports native units (feet, degrees).
struct OurAirportData {
  /// Unique ID from OurAirports database (used as recordID).
  let id: String

  /// FAA location ID (local_code field).
  let localId: String

  /// ICAO identifier if available.
  let ICAO_ID: String?

  /// Airport name.
  let name: String

  /// City/municipality name.
  let municipality: String?

  /// Latitude in decimal degrees.
  let latitude: Double

  /// Longitude in decimal degrees.
  let longitude: Double

  /// Field elevation in feet.
  let elevationFt: Double

  /// Runways at this airport.
  let runways: [OurRunwayData]
}

/// Runway data parsed from OurAirports CSV.
///
/// Contains runway properties needed for performance calculations.
/// Values are in OurAirports native units (feet, degrees).
struct OurRunwayData {
  /// Runway designator (e.g., "09L").
  let name: String

  /// Threshold elevation in feet.
  let elevationFt: Double?

  /// True heading in degrees.
  let trueHeading: Double

  /// Runway length in feet.
  let lengthFt: Double

  /// Displaced threshold distance in feet.
  let displacedThresholdFt: Double

  /// Runway surface type.
  let surfaceType: SurfaceType

  /// Name of the reciprocal runway end.
  let reciprocalName: String?

  /// Threshold latitude in decimal degrees.
  let thresholdLatitude: Double?

  /// Threshold longitude in decimal degrees.
  let thresholdLongitude: Double?

  /// Runway width in feet.
  let widthFt: Double?
}
