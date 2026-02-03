import CoreLocation
import Foundation

/// Processing phases for terrain data.
///
/// Used by ``TerrainRegion/phaseWeight(for:totalTiles:)`` to calculate weighted
/// progress contributions based on measured per-tile processing times.
public enum TerrainPhase: Sendable {
  case downloading
  case parsing
  case compressing
  case uploading
}

/// Represents a terrain region/continent for SRTM data.
///
/// Each region contains one or more bounding boxes that define the geographic extent
/// of SRTM tiles included in the region's terrain data file. Multiple bounding boxes
/// allow precise coverage of non-contiguous areas (e.g., Alaska and Caribbean for North America).
public enum TerrainRegion: String, CaseIterable, Identifiable, Sendable, Codable {
  case indianOcean = "io"
  case midAtlantic = "ma"
  case antarctica = "aq"
  case oceania = "oc"
  case middleEast = "me"
  case australia = "au"
  case southAmerica = "sa"
  case europe = "eu"
  case africa = "af"
  case asia = "as"
  case northAmerica = "na"

  /// Estimated size per tile in bytes (uncompressed SRTM3: 1201×1201×Int16).
  private static let estimatedTileSize = 2_884_802

  // MARK: - Progress Weight Constants

  /// Phase time multipliers based on measured per-tile processing times.
  /// Derived from actual timing data across 40,624 tiles (11 regions, ~12 hours total).
  private static let downloadMultiplier = 0.1395
  private static let combineMultiplier = 0.2219
  private static let compressMultiplier = 0.5468
  private static let uploadMultiplier = 0.0918

  /// Each processing phase's share of region processing time, scaled to 10 000.
  /// Values derived from the multipliers above: download 15.4%, parse 24.4%, compress 60.2%.
  /// Upload (9.2% of overall) is tracked separately in the progress tree.
  public static let downloadPhaseRatio: Int64 = 1536
  public static let parsePhaseRatio: Int64 = 2444
  public static let compressPhaseRatio: Int64 = 6020
  public static let uploadPhaseRatio: Int64 = 918

  /// Returns the terrain region to prefetch based on the device's locale.
  ///
  /// Uses `Locale.current.region?.continent` (UN M49 codes) as a proxy for the
  /// user's geographic region. Defaults to North America when the locale cannot
  /// be determined.
  public static var localePrefetchRegion: Self {
    guard let region = Locale.current.region,
      let continent = region.continent
    else {
      return .northAmerica
    }
    switch continent.identifier {
      case "150": return .europe
      case "002": return .africa
      case "009": return .australia
      case "142":
        // Western Asia → Middle East
        let middleEast: Set<String> = [
          "SA", "AE", "QA", "BH", "KW", "OM", "YE",
          "IQ", "IR", "JO", "LB", "SY", "IL", "PS", "TR", "CY"
        ]
        return middleEast.contains(region.identifier) ? .middleEast : .asia
      case "019":
        // South America
        let southAmerica: Set<String> = [
          "BR", "AR", "CL", "CO", "PE", "VE", "EC",
          "BO", "PY", "UY", "GY", "SR"
        ]
        return southAmerica.contains(region.identifier) ? .southAmerica : .northAmerica
      default:
        return .northAmerica
    }
  }

  // MARK: - Instance Properties

  /// Actual number of successfully downloaded tiles (based on measured data).
  /// This differs from hgtTileNames.count as not all requested tiles exist.
  private var numTiles: Int {
    switch self {
      case .indianOcean: 123
      case .midAtlantic: 68
      case .antarctica: 7042
      case .oceania: 1581
      case .middleEast: 996
      case .australia: 1914
      case .southAmerica: 3062
      case .europe: 3513
      case .africa: 5110
      case .asia: 10509
      case .northAmerica: 6706
    }
  }

  public var id: String { rawValue }

  /// Human-readable display name for the region.
  public var displayName: String {
    switch self {
      case .northAmerica: String(localized: "North America")
      case .southAmerica: String(localized: "South America")
      case .europe: String(localized: "Europe")
      case .asia: String(localized: "Asia")
      case .middleEast: String(localized: "Middle East")
      case .africa: String(localized: "Africa")
      case .australia: String(localized: "Australia")
      case .oceania: String(localized: "Oceania")
      case .midAtlantic: String(localized: "Mid-Atlantic")
      case .indianOcean: String(localized: "Indian Ocean")
      case .antarctica: String(localized: "Antarctica")
    }
  }

  /// Compressed file size in bytes from the bundled manifest.
  public var sizeBytes: Int {
    guard let region = TerrainManifest.bundled.region(forID: rawValue) else {
      fatalError("Region \(rawValue) not found in bundled terrain manifest")
    }
    return region.sizeBytes
  }

  /// Estimated uncompressed file size in bytes based on tile count.
  public var estimatedFileSize: Int {
    hgtTileNames.count * Self.estimatedTileSize
  }

  /// Whether this region should be prefetched on app install.
  public var shouldPrefetch: Bool { self == .northAmerica }

  /// Bounding boxes for the region. Multiple boxes allow precise coverage of non-contiguous areas.
  public var boundingBoxes: [TerrainBoundingBox] {
    switch self {
      case .northAmerica:
        [
          .init(minLat: 7, maxLat: 50, minLon: -130, maxLon: -50),  // Continental US, Mexico, Central America
          .init(minLat: 50, maxLat: 72, minLon: -180, maxLon: -130),  // Alaska
          .init(minLat: 50, maxLat: 56, minLon: 170, maxLon: 180),  // Aleutian Islands (past date line)
          .init(minLat: 50, maxLat: 84, minLon: -130, maxLon: -50),  // Arctic Canada
          .init(minLat: 10, maxLat: 28, minLon: -90, maxLon: -60)  // Caribbean
        ]
      case .southAmerica:
        [
          .init(minLat: -56, maxLat: 7, minLon: -82, maxLon: -34),  // Main continent
          .init(minLat: -4, maxLat: 2, minLon: -92, maxLon: -89),  // Galapagos
          .init(minLat: -5, maxLat: 0, minLon: -35, maxLon: -30)  // Fernando de Noronha
        ]
      case .europe:
        [
          .init(minLat: 35, maxLat: 72, minLon: -10, maxLon: 60),  // Continental Europe
          .init(minLat: 63, maxLat: 67, minLon: -25, maxLon: -13),  // Iceland
          .init(minLat: 59, maxLat: 84, minLon: -74, maxLon: -10),  // Greenland
          .init(minLat: 74, maxLat: 82, minLon: 10, maxLon: 35),  // Svalbard
          .init(minLat: 49, maxLat: 61, minLon: -11, maxLon: 2)  // UK/Ireland
        ]
      case .asia:
        [
          .init(minLat: -10, maxLat: 55, minLon: 60, maxLon: 180),  // East/SE/South Asia
          .init(minLat: 55, maxLat: 82, minLon: 45, maxLon: 180)  // Siberia/Arctic Russia
        ]
      case .middleEast:
        [
          .init(minLat: 12, maxLat: 42, minLon: 34, maxLon: 64),  // Arabian Peninsula, Iran, Iraq
          .init(minLat: 30, maxLat: 42, minLon: 26, maxLon: 45)  // Turkey, Levant
        ]
      case .africa:
        [
          .init(minLat: -35, maxLat: 38, minLon: -18, maxLon: 52)  // Continental Africa
        ]
      case .australia:
        [
          .init(minLat: -44, maxLat: -10, minLon: 112, maxLon: 154),  // Australia mainland
          .init(minLat: -48, maxLat: -34, minLon: 166, maxLon: 179),  // New Zealand
          .init(minLat: -12, maxLat: 0, minLon: 140, maxLon: 156),  // Papua New Guinea
          .init(minLat: -11, maxLat: -10, minLon: 105, maxLon: 106),  // Christmas Island
          .init(minLat: -13, maxLat: -11, minLon: 96, maxLon: 98),  // Cocos Islands
          .init(minLat: -32, maxLat: -29, minLon: 158, maxLon: 160),  // Lord Howe Island
          .init(minLat: -30, maxLat: -28, minLon: 167, maxLon: 169),  // Norfolk Island
          .init(minLat: -23, maxLat: -19, minLon: 163, maxLon: 170),  // New Caledonia
          .init(minLat: -23, maxLat: -10, minLon: 163, maxLon: 172),  // Vanuatu
          .init(minLat: -12, maxLat: -10, minLon: 159, maxLon: 166)  // Solomon Islands
        ]
      case .oceania:
        [
          .init(minLat: 18, maxLat: 25, minLon: -167, maxLon: -154),  // Hawaii
          .init(minLat: -28, maxLat: -8, minLon: -155, maxLon: -134),  // French Polynesia
          .init(minLat: -22, maxLat: -9, minLon: -172, maxLon: -157),  // Cook Islands
          .init(minLat: -25, maxLat: -12, minLon: -180, maxLon: -168),  // Fiji/Samoa/Tonga (west)
          .init(minLat: -25, maxLat: -12, minLon: 175, maxLon: 180),  // Fiji/Tonga (east)
          .init(minLat: -28, maxLat: -26, minLon: -110, maxLon: -108),  // Easter Island
          .init(minLat: 13, maxLat: 21, minLon: 144, maxLon: 146),  // Guam, Marianas
          .init(minLat: 0, maxLat: 10, minLon: 131, maxLon: 172),  // Micronesia/Marshall Islands
          .init(minLat: -45, maxLat: -29, minLon: -180, maxLon: -175),  // Chatham, Raoul (NZ remote)
          .init(minLat: -5, maxLat: 6, minLon: -173, maxLon: -157),  // Kiribati
          .init(minLat: 27, maxLat: 30, minLon: -178, maxLon: -176),  // Midway
          .init(minLat: 5, maxLat: 7, minLon: -163, maxLon: -161)  // Palmyra
        ]
      case .midAtlantic:
        [
          .init(minLat: 36, maxLat: 40, minLon: -32, maxLon: -25),  // Azores
          .init(minLat: 14, maxLat: 18, minLon: -26, maxLon: -22),  // Cabo Verde
          .init(minLat: 27, maxLat: 30, minLon: -19, maxLon: -13),  // Canary Islands
          .init(minLat: 32, maxLat: 34, minLon: -18, maxLon: -15)  // Madeira
        ]
      case .indianOcean:
        [
          .init(minLat: -11, maxLat: -3, minLon: 46, maxLon: 57),  // Seychelles + Agalega
          .init(minLat: -21, maxLat: -19, minLon: 57, maxLon: 64),  // Mauritius
          .init(minLat: -22, maxLat: -20, minLon: 55, maxLon: 56),  // Reunion
          .init(minLat: -1, maxLat: 8, minLon: 72, maxLon: 74),  // Maldives
          .init(minLat: -16, maxLat: -15, minLon: 54, maxLon: 55)  // Tromelin
        ]
      case .antarctica:
        [
          .init(minLat: -90, maxLat: -60, minLon: -180, maxLon: 180)  // Entire continent
        ]
    }
  }

  /// Overall bounding box encompassing all bounding boxes for the region.
  /// Used for binary file header and broad containment checks.
  public var overallBoundingBox: TerrainBoundingBox {
    guard let first = boundingBoxes.first else {
      fatalError("Region must have at least one bounding box")
    }
    return boundingBoxes.dropFirst().reduce(first) { result, box in
      .init(
        minLat: min(result.minLat, box.minLat),
        maxLat: max(result.maxLat, box.maxLat),
        minLon: min(result.minLon, box.minLon),
        maxLon: max(result.maxLon, box.maxLon)
      )
    }
  }

  /// Filename for the terrain data file.
  public var filename: String { "terrain-\(rawValue).srtm.lzma" }

  /// Output filename for the processed terrain file (uncompressed).
  public var outputFilename: String { "terrain-\(rawValue).srtm" }

  /// Compressed output filename.
  public var compressedFilename: String { "\(outputFilename).lzma" }

  /// Returns all HGT tile names that fall within this region's bounding boxes.
  ///
  /// HGT tiles are named by their southwest corner coordinate, e.g., "N45W123.hgt"
  /// This method generates all tile names for SRTM3 (1x1 degree tiles).
  public var hgtTileNames: [String] {
    var tiles = Set<String>()

    for box in boundingBoxes {
      for lat in box.minLat..<box.maxLat {
        for lon in box.minLon..<box.maxLon {
          let latPrefix = lat >= 0 ? "N" : "S",
            lonPrefix = lon >= 0 ? "E" : "W",
            latStr = String(format: "%02d", abs(lat)),
            lonStr = String(format: "%03d", abs(lon))
          tiles.insert("\(latPrefix)\(latStr)\(lonPrefix)\(lonStr)")
        }
      }
    }

    return Array(tiles).sorted()
  }

  // MARK: - Type Methods

  /// Returns all regions that contain the given coordinate.
  ///
  /// Multiple regions may contain the same coordinate where bounding boxes overlap.
  public static func containing(coordinate: CLLocationCoordinate2D) -> [Self] {
    containing(latitude: coordinate.latitude, longitude: coordinate.longitude)
  }

  /// Returns all regions that contain the given coordinate.
  ///
  /// Multiple regions may contain the same coordinate where bounding boxes overlap.
  public static func containing(latitude: Double, longitude: Double) -> [Self] {
    allCases.filter { $0.contains(latitude: latitude, longitude: longitude) }
  }

  /// Sum of numTiles for a collection of regions.
  public static func totalTiles(for regions: [Self]) -> Int {
    regions.reduce(0) { $0 + $1.numTiles }
  }

  // MARK: - Instance Methods

  /// Whether this region contains the given coordinate.
  public func contains(latitude: Double, longitude: Double) -> Bool {
    boundingBoxes.contains { $0.contains(latitude: latitude, longitude: longitude) }
  }

  // MARK: - Progress Weighting

  /// Sum of all three phase weights for this region, proportional to its tile count
  /// relative to the total. Used as ``Progress/pendingUnitCount`` when adding a
  /// per-region child to a processing parent.
  public func totalPhaseWeight(totalTiles: Int) -> Int64 {
    // numTiles / totalTiles gives the region's share; multiply by 10 000 to stay in integer space.
    // The result is the number of units this region should occupy out of the parent's totalUnitCount.
    Int64(round(Double(numTiles) / Double(totalTiles) * 10000))
  }

  /// Returns the weighted progress contribution for each phase of processing this region.
  ///
  /// The weights are based on measured per-tile processing times across 40,624 tiles.
  /// Download (~14%), parsing/combining (~22%), compression (~55%), upload (~9%).
  ///
  /// - Parameters:
  ///   - phase: The processing phase
  ///   - totalTiles: Sum of numTiles for all regions being processed
  /// - Returns: The fraction of total progress this phase contributes (0.0-1.0)
  public func phaseWeight(for phase: TerrainPhase, totalTiles: Int) -> Double {
    let tileWeight = Double(numTiles) / Double(totalTiles)
    switch phase {
      case .downloading: return tileWeight * Self.downloadMultiplier
      case .parsing: return tileWeight * Self.combineMultiplier
      case .compressing: return tileWeight * Self.compressMultiplier
      case .uploading: return tileWeight * Self.uploadMultiplier
    }
  }
}

/// Bounding box for a terrain region.
public struct TerrainBoundingBox: Sendable, Codable, Equatable {
  public let minLat: Int
  public let maxLat: Int
  public let minLon: Int
  public let maxLon: Int

  public init(minLat: Int, maxLat: Int, minLon: Int, maxLon: Int) {
    self.minLat = minLat
    self.maxLat = maxLat
    self.minLon = minLon
    self.maxLon = maxLon
  }

  /// Checks if this bounding box contains the given coordinate.
  public func contains(latitude: Double, longitude: Double) -> Bool {
    let lat = Int(latitude.rounded(.towardZero)),
      lon = Int(longitude.rounded(.towardZero))

    // Handle special case for negative coordinates
    let latCheck = (latitude >= 0 ? lat : lat - 1),
      lonCheck = (longitude >= 0 ? lon : lon - 1)

    return latCheck >= minLat && latCheck < maxLat && lonCheck >= minLon && lonCheck < maxLon
  }
}
