public import CoreLocation
import Foundation

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

  /// Width of one uncompressed SRTM3 tile (1201×1201×Int16), the ceiling a tile compresses under.
  private static let estimatedTileSize = 2_884_802

  /// Distinguishes this app's Background Assets downloads from any other client's.
  private static let downloadIdentifierPrefix = "terrain-"

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

  public var id: String { rawValue }

  /// Human-readable display name for the region.
  public var displayName: String {
    switch self {
      case .northAmerica: String(localized: "North America", bundle: .sharedFramework)
      case .southAmerica: String(localized: "South America", bundle: .sharedFramework)
      case .europe: String(localized: "Europe", bundle: .sharedFramework)
      case .asia: String(localized: "Asia", bundle: .sharedFramework)
      case .middleEast: String(localized: "Middle East", bundle: .sharedFramework)
      case .africa: String(localized: "Africa", bundle: .sharedFramework)
      case .australia: String(localized: "Australia", bundle: .sharedFramework)
      case .oceania: String(localized: "Oceania", bundle: .sharedFramework)
      case .midAtlantic: String(localized: "Mid-Atlantic", bundle: .sharedFramework)
      case .indianOcean: String(localized: "Indian Ocean", bundle: .sharedFramework)
      case .antarctica: String(localized: "Antarctica", bundle: .sharedFramework)
    }
  }

  /// Payload size in bytes from the bundled manifest.
  public var sizeBytes: Int {
    guard let publishedSizeBytes else {
      fatalError("Region \(rawValue) not found in bundled terrain manifest")
    }
    return publishedSizeBytes
  }

  /// Size this region's published payload measures, or `nil` for a region no manifest carries.
  public var publishedSizeBytes: Int? {
    TerrainManifest.bundled.region(forID: rawValue)?.sizeBytes
  }

  /// Roughly what this region's payload occupies, for weighing regions before publishing one.
  ///
  /// A published region reports what it actually measures. Anything else can only be bounded by
  /// the tiles it covers at full width, which overstates a payload whose tiles are compressed.
  public var estimatedFileSize: Int {
    publishedSizeBytes ?? tileNames.count * Self.estimatedTileSize
  }

  /// Bounding boxes for the region. Multiple boxes allow precise coverage of non-contiguous areas.
  public var boundingBoxes: [TerrainBoundingBox] {
    switch self {
      case .northAmerica:
        [
          // Continental US, Mexico, Central America
          .init(minLat: 7, maxLat: 50, minLon: -130, maxLon: -50),
          // Alaska
          .init(minLat: 50, maxLat: 72, minLon: -180, maxLon: -130),
          // Aleutian Islands (past date line)
          .init(minLat: 50, maxLat: 56, minLon: 170, maxLon: 180),
          .init(minLat: 50, maxLat: 84, minLon: -130, maxLon: -50),  // Arctic Canada
          .init(minLat: 10, maxLat: 28, minLon: -90, maxLon: -60),  // Caribbean
          .init(minLat: 5, maxLat: 6, minLon: -88, maxLon: -87)  // Cocos Island
        ]
      case .southAmerica:
        [
          .init(minLat: -56, maxLat: 7, minLon: -82, maxLon: -34),  // Main continent
          .init(minLat: -57, maxLat: -56, minLon: -69, maxLon: -68),  // Diego Ramírez Islands
          .init(minLat: -4, maxLat: 2, minLon: -93, maxLon: -89),  // Galapagos
          .init(minLat: -5, maxLat: 0, minLon: -35, maxLon: -30),  // Fernando de Noronha
          .init(minLat: -21, maxLat: -20, minLon: -30, maxLon: -28),  // Trindade and Martim Vaz
          .init(minLat: -60, maxLat: -56, minLon: -29, maxLon: -26)  // South Sandwich Islands
        ]
      case .europe:
        [
          .init(minLat: 35, maxLat: 72, minLon: -10, maxLon: 60),  // Continental Europe
          .init(minLat: 63, maxLat: 67, minLon: -25, maxLon: -13),  // Iceland
          .init(minLat: 59, maxLat: 84, minLon: -74, maxLon: -10),  // Greenland
          .init(minLat: 81, maxLat: 82, minLon: -10, maxLon: -8),  // Northeast Greenland
          .init(minLat: 74, maxLat: 82, minLon: 10, maxLon: 35),  // Svalbard
          .init(minLat: 49, maxLat: 61, minLon: -11, maxLon: 2)  // UK/Ireland
        ]
      case .asia:
        [
          .init(minLat: -10, maxLat: 55, minLon: 60, maxLon: 180),  // East/SE/South Asia
          .init(minLat: 55, maxLat: 82, minLon: 45, maxLon: 180),  // Siberia/Arctic Russia
          .init(minLat: 80, maxLat: 82, minLon: 35, maxLon: 45)  // Franz Josef Land
        ]
      case .middleEast:
        [
          .init(minLat: 12, maxLat: 42, minLon: 34, maxLon: 64),  // Arabian Peninsula, Iran, Iraq
          .init(minLat: 30, maxLat: 42, minLon: 26, maxLon: 45)  // Turkey, Levant
        ]
      case .africa:
        [
          .init(minLat: -35, maxLat: 38, minLon: -18, maxLon: 52),  // Continental Africa
          .init(minLat: -38, maxLat: -37, minLon: -13, maxLon: -12),  // Tristan da Cunha
          .init(minLat: -41, maxLat: -40, minLon: -11, maxLon: -9),  // Gough Island
          .init(minLat: -55, maxLat: -54, minLon: 3, maxLon: 4)  // Bouvet Island
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
          .init(minLat: -12, maxLat: -10, minLon: 159, maxLon: 166),  // Solomon Islands
          .init(minLat: -24, maxLat: -17, minLon: 154, maxLon: 156),  // Coral Sea Islands
          .init(minLat: -22, maxLat: -19, minLon: 158, maxLon: 160),  // Chesterfield Islands
          .init(minLat: -19, maxLat: -17, minLon: 162, maxLon: 163),  // Entrecasteaux Reefs
          .init(minLat: -23, maxLat: -22, minLon: 172, maxLon: 173),  // Matthew and Hunter
          .init(minLat: -51, maxLat: -48, minLon: 165, maxLon: 167),  // Auckland, Snares
          .init(minLat: -50, maxLat: -47, minLon: 178, maxLon: 180),  // Antipodes, Bounty
          .init(minLat: -53, maxLat: -52, minLon: 168, maxLon: 170),  // Campbell Island
          .init(minLat: -56, maxLat: -54, minLon: 158, maxLon: 159)  // Macquarie Island
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
          // Chatham, Raoul (NZ remote)
          .init(minLat: -45, maxLat: -29, minLon: -180, maxLon: -175),
          .init(minLat: -5, maxLat: 6, minLon: -173, maxLon: -157),  // Kiribati
          .init(minLat: 27, maxLat: 30, minLon: -178, maxLon: -176),  // Midway
          .init(minLat: 5, maxLat: 7, minLon: -163, maxLon: -161),  // Palmyra
          .init(minLat: 24, maxLat: 29, minLon: -180, maxLon: -167),  // NW Hawaiian Islands
          .init(minLat: 16, maxLat: 17, minLon: -170, maxLon: -169),  // Johnston Atoll
          .init(minLat: 0, maxLat: 1, minLon: -177, maxLon: -176),  // Howland, Baker
          .init(minLat: -9, maxLat: -8, minLon: -173, maxLon: -172),  // Tokelau
          .init(minLat: -5, maxLat: -3, minLon: -175, maxLon: -174),  // Phoenix Islands
          .init(minLat: -9, maxLat: -8, minLon: -159, maxLon: -157),  // Penrhyn
          .init(minLat: -6, maxLat: -3, minLon: -156, maxLon: -154),  // Southern Line Islands
          .init(minLat: -8, maxLat: -7, minLon: -141, maxLon: -140),  // Northern Marquesas
          .init(minLat: -26, maxLat: -23, minLon: -131, maxLon: -128),  // Pitcairn Islands
          .init(minLat: -25, maxLat: -24, minLon: -125, maxLon: -124),  // Ducie Island
          .init(minLat: -27, maxLat: -26, minLon: -106, maxLon: -105),  // Salas y Gómez
          .init(minLat: -11, maxLat: -10, minLon: 179, maxLon: 180)  // Southern Tuvalu
        ]
      case .midAtlantic:
        [
          .init(minLat: 36, maxLat: 40, minLon: -32, maxLon: -24),  // Azores
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
          .init(minLat: -16, maxLat: -15, minLon: 54, maxLon: 55),  // Tromelin
          .init(minLat: -17, maxLat: -16, minLon: 59, maxLon: 60),  // Cargados Carajos
          .init(minLat: -39, maxLat: -37, minLon: 77, maxLon: 78),  // Amsterdam, Saint-Paul
          .init(minLat: -47, maxLat: -46, minLon: 37, maxLon: 39),  // Prince Edward Islands
          .init(minLat: -47, maxLat: -45, minLon: 50, maxLon: 53),  // Crozet Islands
          .init(minLat: -51, maxLat: -48, minLon: 68, maxLon: 71),  // Kerguelen Islands
          .init(minLat: -54, maxLat: -52, minLon: 72, maxLon: 74)  // Heard and McDonald Islands
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

  /// Name this region's payload is published under, and the name the manifest refers to it by.
  public var remoteFilename: String { "terrain-\(rawValue).srtm" }

  /// Name of the file an asset pack carries beside this region's payload, holding the payload's
  /// ``TerrainPayloadDigest``.
  public var digestFilename: String { "\(remoteFilename).sha256" }

  /// Name this region's payload is stored under in the shared container.
  public var localFilename: String { "\(rawValue).srtm" }

  /// Identifies this region's download to Background Assets, in the app and its extension alike.
  public var downloadIdentifier: String { Self.downloadIdentifierPrefix + rawValue }

  /// Names of every 1×1 degree tile within this region's bounding boxes, each named for its
  /// southwest corner, e.g. "N45W123". The region's payload holds one tile for each.
  public var tileNames: [String] {
    var tiles = Set<String>()

    for box in boundingBoxes {
      for lat in box.minLat..<box.maxLat {
        for lon in box.minLon..<box.maxLon {
          let latPrefix = lat >= 0 ? "N" : "S",
            lonPrefix = lon >= 0 ? "E" : "W",
            latStr = unsafe String(format: "%02d", abs(lat)),
            lonStr = unsafe String(format: "%03d", abs(lon))
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

  /// Number of tiles in a collection of regions' payloads.
  public static func totalTiles(for regions: [Self]) -> Int {
    regions.reduce(0) { $0 + $1.tileNames.count }
  }

  /// The region a Background Assets download identifier refers to, if it is one of this app's.
  public static func region(forDownloadIdentifier identifier: String) -> Self? {
    guard identifier.hasPrefix(downloadIdentifierPrefix) else { return nil }
    return .init(rawValue: String(identifier.dropFirst(downloadIdentifierPrefix.count)))
  }

  // MARK: - Instance Methods

  /// Whether this region contains the given coordinate.
  public func contains(latitude: Double, longitude: Double) -> Bool {
    boundingBoxes.contains { $0.contains(latitude: latitude, longitude: longitude) }
  }

  // MARK: - Progress Weighting

  /// Sum of all three phase weights for this region, proportional to its tile count
  /// relative to the total. Used as `Progress.pendingUnitCount` when adding a
  /// per-region child to a processing parent.
  public func totalPhaseWeight(totalTiles: Int) -> Int64 {
    // The region's share of the tiles, times 10 000 to stay in integer space: the number of units
    // this region should occupy out of the parent's totalUnitCount.
    Int64(round(Double(tileNames.count) / Double(totalTiles) * 10000))
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
  ///
  /// The box spans whole one-degree tiles, so it holds its south and west edges but not its north
  /// and east ones, which belong to the tiles beyond.
  public func contains(latitude: Double, longitude: Double) -> Bool {
    (Double(minLat)..<Double(maxLat)).contains(latitude)
      && (Double(minLon)..<Double(maxLon)).contains(longitude)
  }
}
