import Foundation
import Gzip
import RegexBuilder
import ZIPFoundation

/// Errors that can occur during HGT file parsing.
enum HGTParserError: LocalizedError {
  case invalidFileSize(expected: Int64, actual: Int64)
  case invalidFilename(String)
  case readError(Error)
  case decompressionError(Error)
  case hgtFileNotFoundInArchive

  var errorDescription: String? {
    String(localized: "Failed to process HGT data.")
  }

  var failureReason: String? {
    switch self {
      case .invalidFileSize(let expected, let actual):
        return String(
          localized:
            "File size was invalid: Expected \(expected, format: .byteCount(style: .file)) but got \(actual, format: .byteCount(style: .file))."
        )
      case .invalidFilename(let name):
        return String(localized: "The filename “\(name)” does not match the expected HGT format.")
      case .readError(let error):
        return String(localized: "Read error: \(error.localizedDescription)")
      case .decompressionError(let error):
        return String(localized: "Decompression error: \(error.localizedDescription)")
      case .hgtFileNotFoundInArchive:
        return String(localized: "No .hgt file found in ZIP archive.")
    }
  }
}

/// Parser for SRTM HGT (Height) files.
///
/// HGT files contain elevation data in a simple binary format:
/// - Big-endian signed 16-bit integers
/// - Row-major order from north to south
/// - SRTM1: 3601x3601 samples (1 arc-second resolution)
/// - SRTM3: 1201x1201 samples (3 arc-second resolution)
///
/// Each file covers a 1×1 degree tile, named by the southwest corner coordinate.
/// For example, "N45W123.hgt" covers latitude 45–46° N, longitude 123–122° W.
///
/// Reference: https://www.usgs.gov/faqs/what-are-hgt-files
enum HGTParser {

  // MARK: - Private Properties

  /// Regex pattern for parsing HGT tile names (e.g., "N45W123")
  private static let tileNamePattern = Regex {
    Capture { One(.anyOf("NS")) }
    Capture { OneOrMore(.digit) }
    Capture { One(.anyOf("EW")) }
    Capture { OneOrMore(.digit) }
  }

  // MARK: - Type Methods

  /// Parses an HGT file from raw data.
  /// - Parameters:
  ///   - data: Raw HGT file data (uncompressed)
  ///   - name: Tile name (e.g., "N45W123")
  /// - Returns: Parsed tile data
  /// - Throws: HGTParserError if the file is invalid
  static func parse(data: Data, name: String) throws -> Tile {
    // Parse coordinates from name
    let coords = try parseCoordinates(from: name)
    let latitude = coords.latitude
    let longitude = coords.longitude

    // Determine resolution from file size
    let resolution: Resolution
    switch Int64(data.count) {
      case Resolution.srtm1.bytesPerFile:
        resolution = .srtm1
      case Resolution.srtm3.bytesPerFile:
        resolution = .srtm3
      default:
        throw HGTParserError.invalidFileSize(
          expected: Resolution.srtm3.bytesPerFile,
          actual: Int64(data.count)
        )
    }

    // Parse elevation data (big-endian Int16 values)
    var raw = [Int16]()
    raw.reserveCapacity(resolution.totalSamples)

    data.withUnsafeBytes { buffer in
      let int16Buffer = buffer.bindMemory(to: UInt16.self)
      for i in 0..<resolution.totalSamples {
        // Convert from big-endian to host byte order
        let bigEndianValue = int16Buffer[i]
        let hostValue = Int16(bitPattern: UInt16(bigEndian: bigEndianValue))
        raw.append(hostValue)
      }
    }

    let elevations = Elevations(storage: raw, size: resolution.samplesPerSide)

    return Tile(
      name: name,
      latitude: latitude,
      longitude: longitude,
      resolution: resolution,
      elevations: elevations
    )
  }

  /// Parses an HGT file from a URL.
  /// - Parameters:
  ///   - url: URL to the HGT file (may be `.hgt`, `.hgt.zip`, or `.hgt.gz`)
  /// - Returns: Parsed tile data
  /// - Throws: ``HGTParserError`` if the file cannot be read or parsed
  static func parse(contentsOf url: URL) throws -> Tile {
    let name = extractTileName(from: url)

    let data =
      if url.pathExtension == "zip" {
        // Handle zipped HGT files
        try decompressZip(at: url)
      } else if url.pathExtension == "gz" {
        // Handle gzip compressed HGT files
        try decompressGzip(at: url)
      } else {
        try Data(contentsOf: url)
      }

    return try parse(data: data, name: name)
  }

  /// Parses latitude and longitude from a tile name.
  /// - Parameter name: Tile name (e.g., "N45W123")
  /// - Returns: Parsed coordinates
  /// - Throws: HGTParserError if the name format is invalid
  static func parseCoordinates(from name: String) throws -> Coordinates {
    guard let match = try? tileNamePattern.wholeMatch(in: name.uppercased()) else {
      throw HGTParserError.invalidFilename(name)
    }

    guard let latValue = Int(match.2),
      let lonValue = Int(match.4)
    else {
      throw HGTParserError.invalidFilename(name)
    }

    let latitude = match.1 == "N" ? latValue : -latValue,
      longitude = match.3 == "E" ? lonValue : -lonValue

    return Coordinates(latitude: latitude, longitude: longitude)
  }

  /// Extracts the tile name from a URL.
  /// - Parameter url: URL to the HGT file
  /// - Returns: Tile name (e.g., "N45W123")
  private static func extractTileName(from url: URL) -> String {
    var name = url.deletingPathExtension().lastPathComponent
    // Remove any additional extensions (e.g., .hgt from .hgt.zip)
    if name.hasSuffix(".hgt") {
      name = String(name.dropLast(4))
    }
    return name.uppercased()
  }

  /// Decompresses a zipped HGT file using ZIPFoundation.
  /// - Parameter url: URL to the .hgt.zip file
  /// - Returns: Decompressed HGT data
  /// - Throws: HGTParserError if decompression fails
  private static func decompressZip(at url: URL) throws -> Data {
    do {
      let archive = try Archive(url: url, accessMode: .read)

      // Find the .hgt file in the archive (SRTM ZIPs typically contain one .hgt file)
      guard let hgtEntry = archive.first(where: { $0.path.hasSuffix(".hgt") }) else {
        throw HGTParserError.hgtFileNotFoundInArchive
      }

      // Extract the HGT data
      var hgtData = Data()
      _ = try archive.extract(hgtEntry) { data in
        hgtData.append(data)
      }

      return hgtData
    } catch let error as HGTParserError {
      throw error
    } catch {
      throw HGTParserError.decompressionError(error)
    }
  }

  /// Decompresses a gzip compressed HGT file.
  /// - Parameter url: URL to the .hgt.gz file
  /// - Returns: Decompressed HGT data
  /// - Throws: HGTParserError if decompression fails
  private static func decompressGzip(at url: URL) throws -> Data {
    do {
      let compressedData = try Data(contentsOf: url)
      return try compressedData.gunzipped()
    } catch {
      throw HGTParserError.decompressionError(error)
    }
  }

  // MARK: - Nested Types

  /// SRTM resolution types.
  enum Resolution: Int {
    /// 1 arc-second (~30m) resolution - 3601x3601 samples
    case srtm1 = 3601
    /// 3 arc-second (~90m) resolution - 1201x1201 samples
    case srtm3 = 1201

    var samplesPerSide: Int { rawValue }
    var totalSamples: Int { rawValue * rawValue }
    var bytesPerFile: Int64 { Int64(totalSamples * 2) }  // 16-bit integers
  }

  /// Parsed HGT tile data.
  struct Tile: Sendable {
    /// Tile name (e.g., "N45W123")
    let name: String

    /// Southwest corner latitude in degrees
    let latitude: Int

    /// Southwest corner longitude in degrees
    let longitude: Int

    /// Resolution of the tile data
    let resolution: Resolution

    /// Elevation data as Int16 values (row-major, north to south).
    /// Values are in meters. ``Elevations/voidValue`` indicates void/no data.
    let elevations: Elevations
  }

  /// Parsed tile coordinates.
  struct Coordinates {
    let latitude: Int
    let longitude: Int
  }
}
