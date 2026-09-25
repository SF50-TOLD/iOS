import Foundation
import RegexBuilder
import SF50_Shared

/// A one-degree terrain tile, identified by its southwest corner.
struct TileCoordinates: Hashable, Sendable {

  // MARK: - Type Properties

  /// Matches the corner in a Copernicus tile name: `{N|S}{lat:02}_00_{E|W}{lon:03}_00`.
  private static let copernicusCornerPattern = Regex {
    Capture { One(.anyOf("NS")) }
    TryCapture {
      Repeat(.digit, count: 2)
    } transform: {
      Int($0)
    }
    "_00_"
    Capture { One(.anyOf("EW")) }
    TryCapture {
      Repeat(.digit, count: 3)
    } transform: {
      Int($0)
    }
    "_00"
  }

  // MARK: - Instance Properties

  let latitude: Int
  let longitude: Int

  /// The corner as Copernicus tile names spell it, e.g. `N45_00_W123_00`.
  var copernicusName: String {
    let ns = latitude >= 0 ? "N" : "S",
      ew = longitude >= 0 ? "E" : "W",
      lat = unsafe String(format: "%02d", abs(latitude)),
      lon = unsafe String(format: "%03d", abs(longitude))
    return "\(ns)\(lat)_00_\(ew)\(lon)_00"
  }

  // MARK: - Initializers

  init(latitude: Int, longitude: Int) {
    self.latitude = latitude
    self.longitude = longitude
  }

  /// Reads the corner out of a Copernicus tile name, or fails for any other text.
  init?(copernicusTileName name: some StringProtocol) {
    guard let match = String(name).firstMatch(of: Self.copernicusCornerPattern) else {
      return nil
    }
    let (_, ns, lat, ew, lon) = match.output
    self.init(latitude: ns == "S" ? -lat : lat, longitude: ew == "W" ? -lon : lon)
  }
}

/// What a tile's elevations are read from.
enum TileContent: Sendable {
  /// A downloaded Copernicus GeoTIFF.
  case geoTIFF(URL)
  /// Open sea, whose surface is at sea level throughout.
  case seaLevel
}

/// Reference to a tile's content (keeps only metadata in memory).
struct TileReference: Sendable {
  let content: TileContent
  let coordinates: TileCoordinates
}

/// Result of parsing a single tile.
struct ParsedTile: Sendable {
  let index: Int
  let elevations: Elevations?  // nil if parsing failed
  let error: (any Error)?
  let coordinates: TileCoordinates
}

extension TerrainRegion {
  /// Every one-degree tile inside the region's bounding boxes, south to north then west to east.
  var tileCoordinates: [TileCoordinates] {
    let tiles = boundingBoxes.flatMap { box in
      (box.minLat..<box.maxLat).flatMap { latitude in
        (box.minLon..<box.maxLon).map { TileCoordinates(latitude: latitude, longitude: $0) }
      }
    }
    return Set(tiles).sorted { ($0.latitude, $0.longitude) < ($1.latitude, $1.longitude) }
  }
}
