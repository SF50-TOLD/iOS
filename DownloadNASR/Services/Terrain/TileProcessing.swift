import Foundation

/// Static helper functions for CPU-bound tile processing.
///
/// These functions are extracted from the actor to allow true parallelism
/// via TaskGroup. Actor-isolated methods serialize on the actor's executor,
/// but these static functions can run concurrently on the cooperative thread pool.
enum TileProcessing {

  /// Reads a tile's elevations onto the output grid. Returns parsed elevations or error.
  static func parseTile(
    _ tileRef: TileReference,
    index: Int,
    samplesPerSide: Int
  ) -> ParsedTile {
    do {
      let elevations =
        switch tileRef.content {
          case .geoTIFF(let fileURL):
            try GeoTIFFParser.parse(contentsOf: fileURL).resampled(toSquareOfSize: samplesPerSide)
          case .seaLevel:
            Elevations(size: samplesPerSide, fill: 0)
        }
      return ParsedTile(
        index: index,
        elevations: elevations,
        error: nil,
        coordinates: tileRef.coordinates
      )
    } catch {
      return ParsedTile(
        index: index,
        elevations: nil,
        error: error,
        coordinates: tileRef.coordinates
      )
    }
  }
}
