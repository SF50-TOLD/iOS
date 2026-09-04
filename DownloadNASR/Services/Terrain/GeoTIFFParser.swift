import Foundation
@preconcurrency import RegexBuilder
import TIFF

/// Errors that can occur during GeoTIFF parsing.
enum GeoTIFFParserError: LocalizedError {
  case invalidData
  case readFailed(any Error)
  case noRasterData
  case invalidDimensions(width: Int, height: Int)
  case coordinateParsingFailed(String)

  var errorDescription: String? {
    String(localized: "Failed to process GeoTIFF data.")
  }

  var failureReason: String? {
    switch self {
      case .invalidData:
        return String(localized: "The file does not contain valid TIFF data.")
      case .readFailed(let error):
        return String(localized: "Failed to read TIFF: \(error.localizedDescription)")
      case .noRasterData:
        return String(localized: "No raster data found in TIFF file.")
      case .invalidDimensions(let width, let height):
        return String(
          localized: "Invalid dimensions: \(width, format: .number)×\(height, format: .number)"
        )
      case .coordinateParsingFailed(let filename):
        return String(localized: "Cannot parse coordinates from filename: \(filename)")
    }
  }
}

/// Parser for Copernicus GLO-30 GeoTIFF elevation files.
///
/// Uses tiff-ios library for robust TIFF parsing including:
/// - DEFLATE compression
/// - Floating point predictor (predictor=3)
/// - Tiled and stripped organization
/// - Various sample formats
enum GeoTIFFParser {

  /// Regex pattern for parsing Copernicus GLO-30 filenames.
  /// Matches: `{N|S}{lat:02d}_00_{E|W}{lon:03d}_00`
  private static let coordinatePattern = Regex {
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

  // MARK: - Public API

  /// Parses a GeoTIFF file and extracts elevation data.
  /// - Parameter url: URL to the GeoTIFF file
  /// - Returns: Parsed tile data with Int16 elevations
  static func parse(contentsOf url: URL) throws -> Tile {
    let data = try Data(contentsOf: url)
    return try parse(data: data, filename: url.lastPathComponent)
  }

  /// Parses GeoTIFF data and extracts elevation data.
  /// - Parameters:
  ///   - data: Raw GeoTIFF file data
  ///   - filename: Original filename (used for coordinate extraction)
  /// - Returns: Parsed tile data with Int16 elevations
  static func parse(data: Data, filename: String) throws -> Tile {
    // Parse TIFF using tiff-ios
    guard let tiffImage = TIFFReader.readTiff(from: data) else {
      throw GeoTIFFParserError.invalidData
    }

    // Get the first (and typically only) image directory
    guard let directory = tiffImage.fileDirectories().first else {
      throw GeoTIFFParserError.invalidData
    }

    // Get dimensions
    let width = Int(truncating: directory.imageWidth() as NSNumber),
      height = Int(truncating: directory.imageHeight() as NSNumber)

    guard width > 0, height > 0 else {
      throw GeoTIFFParserError.invalidDimensions(width: width, height: height)
    }

    // Read raster data
    guard let rasters = directory.readRasters() else {
      throw GeoTIFFParserError.noRasterData
    }

    guard rasters.hasSampleValues() else {
      throw GeoTIFFParserError.noRasterData
    }

    // Convert to Int16 elevations
    let int16Elevations = extractElevations(from: rasters)

    // Extract coordinates from filename
    let coords = try parseCoordinates(from: filename)

    return Tile(
      latitude: coords.latitude,
      longitude: coords.longitude,
      elevations: int16Elevations
    )
  }

  // MARK: - Private Helpers

  /// Extracts elevation values from rasters and converts to an ``Elevations`` grid.
  private static func extractElevations(from rasters: TIFFRasters) -> Elevations {
    let width = Int(rasters.width())
    let height = Int(rasters.height())
    let totalPixels = width * height
    var raw = [Int16](repeating: Elevations.voidValue, count: totalPixels)

    // Get sample values (array of arrays, one per sample band)
    guard let allSamples = rasters.sampleValues(),
      !allSamples.isEmpty,
      let sampleValues = allSamples.first
    else {
      return Elevations(storage: raw, width: width, height: height)
    }

    for i in 0..<min(sampleValues.count, totalPixels) {
      let value = sampleValues[i]

      // Handle different numeric types
      let floatValue: Float
      if let f = value as? Float {
        floatValue = f
      } else if let d = value as? Double {
        floatValue = Float(d)
      } else if let n = value as? NSNumber {
        floatValue = n.floatValue
      } else {
        continue  // Unknown type, leave as void
      }

      // Convert to Int16, treating NaN and out-of-range as void
      if floatValue.isNaN || floatValue < -32767 || floatValue > 32767 {
        raw[i] = Elevations.voidValue
      } else {
        raw[i] = Int16(floatValue.rounded())
      }
    }

    return Elevations(storage: raw, width: width, height: height)
  }

  /// Parses coordinates from Copernicus GLO-30 filename.
  ///
  /// Format: `Copernicus_DSM_COG_10_{N|S}{lat:02d}_00_{E|W}{lon:03d}_00_DEM.tif`
  /// Example: `Copernicus_DSM_COG_10_N64_00_W022_00_DEM.tif` → (64, -22)
  static func parseCoordinates(from filename: String) throws -> (latitude: Int, longitude: Int) {
    guard let match = filename.firstMatch(of: coordinatePattern) else {
      throw GeoTIFFParserError.coordinateParsingFailed(filename)
    }

    let (_, ns, latValue, ew, lonValue) = match.output,
      latitude = ns == "N" ? latValue : -latValue,
      longitude = ew == "E" ? lonValue : -lonValue

    return (latitude, longitude)
  }

  // MARK: - Nested Types

  /// Parsed GeoTIFF tile data.
  struct Tile: Sendable {
    /// Southwest corner latitude in degrees
    let latitude: Int

    /// Southwest corner longitude in degrees
    let longitude: Int

    /// Elevation data as a grid of Int16 values (row-major, north to south).
    /// Values are in meters. ``Elevations/voidValue`` indicates no data.
    let elevations: Elevations
  }
}
