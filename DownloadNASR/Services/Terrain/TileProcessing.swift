import Foundation

/// Static helper functions for CPU-bound tile processing.
///
/// These functions are extracted from the actor to allow true parallelism
/// via TaskGroup. Actor-isolated methods serialize on the actor's executor,
/// but these static functions can run concurrently on the cooperative thread pool.
enum TileProcessing {

  /// Parses a single tile from disk. Returns parsed elevations or error.
  static func parseTile(
    _ tileRef: TileReference,
    index: Int,
    outputResolution: HGTParser.Resolution
  ) -> ParsedTile {
    do {
      let elevations: Elevations

      switch tileRef.format {
        case .geoTIFF:
          // Parse GeoTIFF (Copernicus GLO-30)
          let geoTile = try GeoTIFFParser.parse(contentsOf: tileRef.fileURL)

          // Resample to output resolution (handles both downsampling and non-square tiles)
          let targetSize = outputResolution.samplesPerSide
          if geoTile.elevations.width != targetSize || geoTile.elevations.height != targetSize {
            elevations = geoTile.elevations.resampled(toSquareOfSize: targetSize)
          } else {
            elevations = geoTile.elevations
          }
        case .hgt:
          // Parse HGT (SRTM)
          let tile = try HGTParser.parse(contentsOf: tileRef.fileURL)

          // Downsample if needed (SRTM1 -> SRTM3)
          if tile.resolution == .srtm1 && outputResolution == .srtm3 {
            elevations = tile.elevations.downsampled(
              toSize: outputResolution.samplesPerSide,
              blockSize: 3
            )
          } else {
            elevations = tile.elevations
          }
      }

      return ParsedTile(
        index: index,
        elevations: elevations,
        error: nil,
        latitude: tileRef.latitude,
        longitude: tileRef.longitude
      )
    } catch {
      return ParsedTile(
        index: index,
        elevations: nil,
        error: error,
        latitude: tileRef.latitude,
        longitude: tileRef.longitude
      )
    }
  }
}
