import Foundation

/// The source format of a downloaded terrain tile.
enum TileFormat: Sendable {
  case hgt
  case geoTIFF
}

/// Reference to a downloaded tile file (keeps only metadata in memory).
struct TileReference: Sendable {
  let fileURL: URL
  let latitude: Int
  let longitude: Int
  let format: TileFormat
}

/// Result of parsing a single tile.
struct ParsedTile: Sendable {
  let index: Int
  let elevations: Elevations?  // nil if parsing failed
  let error: (any Error)?
  let latitude: Int
  let longitude: Int
}
