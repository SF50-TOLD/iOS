import Foundation
import os

/// Provides O(1) coordinate-to-elevation lookups from a terrain data file.
///
/// The terrain file is opened once at initialization and individual elevation
/// samples are read on demand via `pread`. Only the header and tile index
/// (~100 KB) are held in memory — the multi-gigabyte elevation data stays on
/// disk, avoiding virtual-memory limits on iOS.
///
/// ## File Format
///
/// The terrain file format is:
/// ```
/// Header (20 bytes):
///   - Magic: "SRTM" (4 bytes)
///   - Version: UInt16
///   - Resolution: UInt16 (samples per tile side, e.g., 1201 for SRTM3)
///   - Tile count: UInt32
///   - Bounding box: 4 x Int16 (minLat, maxLat, minLon, maxLon)
///
/// Tile index (12 bytes per tile):
///   - Latitude: Int16 (SW corner)
///   - Longitude: Int16 (SW corner)
///   - Data offset: UInt32 (from file start)
///   - Data length: UInt32
///
/// Tile data:
///   - Int16 elevations, row-major from north to south
/// ```
final class MappedTerrainTile: Sendable {

  // MARK: - Type Properties

  /// SRTM void/no-data sentinel value.
  private static let voidValue: Int16 = -32768

  /// Logger for debug output.
  private static let logger = Logger(
    subsystem: "codes.tim.SF50-TOLD",
    category: "MappedTerrainTile"
  )

  // MARK: - Instance Properties

  /// Open file descriptor for the terrain data file.
  private let file: FileDescriptorBox

  /// Total size of the terrain file in bytes.
  private let fileSize: Int

  /// Resolution (samples per tile side).
  let resolution: Int

  /// Number of tiles in the file.
  let tileCount: Int

  /// Bounding box of the region.
  let boundingBox: TerrainBoundingBox

  /// Tile index for fast lookup.
  private let tileIndex: [TileIndexEntry]

  // MARK: - Initializers

  /// Creates a terrain tile reader from a file URL.
  init(fileURL: URL) throws {
    let fd = Darwin.open(fileURL.path, O_RDONLY)
    guard fd >= 0 else {
      let posixErrno = errno
      Self.logger.error(
        "Failed to open \(fileURL.lastPathComponent): errno \(posixErrno) (\(String(cString: strerror(posixErrno))))"
      )
      throw TerrainServiceError.fileReadError(
        NSError(domain: NSPOSIXErrorDomain, code: Int(posixErrno))
      )
    }
    self.file = FileDescriptorBox(fd)

    // File size for bounds checking
    var sb = stat()
    guard fstat(fd, &sb) == 0 else {
      throw TerrainServiceError.fileReadError(
        NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
      )
    }
    self.fileSize = Int(sb.st_size)

    // Read and parse header (20 bytes)
    guard let headerData = Self.preadData(fd: fd, count: 20, offset: 0) else {
      throw TerrainServiceError.invalidFile(fileURL)
    }
    var reader = BinaryDataReader(data: headerData)

    guard (try? reader.readASCII(4)) == "SRTM" else {
      throw TerrainServiceError.invalidFile(fileURL)
    }
    guard let version = try? reader.readUInt16(), version == 1 || version == 2 else {
      throw TerrainServiceError.invalidFile(fileURL)
    }

    self.resolution = try Int(reader.readUInt16())
    self.tileCount = try Int(reader.readUInt32())
    self.boundingBox = TerrainBoundingBox(
      minLat: try Int(reader.readInt16()),
      maxLat: try Int(reader.readInt16()),
      minLon: try Int(reader.readInt16()),
      maxLon: try Int(reader.readInt16())
    )

    // Read tile index
    // Version 1: 12 bytes per entry (lat:2 + lon:2 + offset:4 + length:4)
    // Version 2: 16 bytes per entry (lat:2 + lon:2 + offset:8 + length:4)
    let entrySize = version == 1 ? 12 : 16
    let indexSize = tileCount * entrySize
    let headerSize = off_t(reader.offset)
    guard let indexData = Self.preadData(fd: fd, count: indexSize, offset: headerSize) else {
      throw TerrainServiceError.invalidFile(fileURL)
    }

    var indexReader = BinaryDataReader(data: indexData)
    var index = [TileIndexEntry]()
    index.reserveCapacity(tileCount)

    for _ in 0..<tileCount {
      let lat = try indexReader.readInt16()
      let lon = try indexReader.readInt16()

      let dataOffset: UInt64
      let dataLength: UInt32

      if version == 1 {
        dataOffset = try UInt64(indexReader.readUInt32())
        dataLength = try indexReader.readUInt32()
      } else {
        dataOffset = try indexReader.readUInt64()
        dataLength = try indexReader.readUInt32()
      }

      index.append(
        .init(
          latitude: lat,
          longitude: lon,
          dataOffset: dataOffset,
          dataLength: dataLength
        )
      )
    }

    self.tileIndex = index

    Self.logger.info(
      "Opened \(fileURL.lastPathComponent): \(self.tileCount) tiles, resolution \(self.resolution), \(self.fileSize) bytes"
    )
  }

  // MARK: - Type Methods

  /// Reads `count` bytes from a file descriptor at the given offset.
  private static func preadData(fd: CInt, count: Int, offset: off_t) -> Data? {
    var buffer = [UInt8](repeating: 0, count: count)
    let bytesRead = pread(fd, &buffer, count, offset)
    guard bytesRead == count else { return nil }
    return Data(buffer)
  }

  // MARK: - Public API

  /// Returns the elevation at the given coordinate.
  /// - Parameters:
  ///   - latitude: The latitude to query
  ///   - longitude: The longitude to query
  /// - Returns: Elevation in meters, or nil if no data available
  func elevation(at latitude: Double, longitude: Double) -> Int16? {
    guard let (entry, latOffset, lonOffset) = tileEntry(for: latitude, longitude: longitude) else {
      return nil
    }

    // Calculate row (from north) and column
    let row = Int((1.0 - latOffset) * Double(resolution - 1)),
      col = Int(lonOffset * Double(resolution - 1))

    // Clamp to valid range
    let clampedRow = max(0, min(resolution - 1, row)),
      clampedCol = max(0, min(resolution - 1, col))

    return sample(row: clampedRow, col: clampedCol, in: entry)
  }

  /// Returns bilinear interpolated elevation at the given coordinate.
  /// - Parameters:
  ///   - latitude: The latitude to query
  ///   - longitude: The longitude to query
  /// - Returns: Interpolated elevation in meters, or nil if no data available
  func interpolatedElevation(at latitude: Double, longitude: Double) -> Double? {
    guard let (entry, latOffset, lonOffset) = tileEntry(for: latitude, longitude: longitude) else {
      return nil
    }

    // Calculate exact position
    let exactRow = (1.0 - latOffset) * Double(resolution - 1),
      exactCol = lonOffset * Double(resolution - 1)

    let (rowInt, rowFrac) = modf(exactRow),
      (colInt, colFrac) = modf(exactCol)

    let row0 = Int(rowInt),
      col0 = Int(colInt),
      row1 = min(row0 + 1, resolution - 1),
      col1 = min(col0 + 1, resolution - 1)

    // Sample four corners
    guard let e00 = sample(row: row0, col: col0, in: entry),
      let e01 = sample(row: row0, col: col1, in: entry),
      let e10 = sample(row: row1, col: col0, in: entry),
      let e11 = sample(row: row1, col: col1, in: entry)
    else {
      return nil
    }

    return bilinearInterpolate(
      topLeft: Double(e00),
      topRight: Double(e01),
      bottomLeft: Double(e10),
      bottomRight: Double(e11),
      rowFrac: rowFrac,
      colFrac: colFrac
    )
  }

  // MARK: - Private Helpers

  /// Finds the tile entry containing the given coordinate.
  private func tileEntry(
    for latitude: Double,
    longitude: Double
  ) -> (entry: TileIndexEntry, latOffset: Double, lonOffset: Double)? {
    let tileLat = Int16(latitude >= 0 ? latitude : latitude - 1),
      tileLon = Int16(longitude >= 0 ? longitude : longitude - 1)

    guard let entry = tileIndex.first(where: { $0.latitude == tileLat && $0.longitude == tileLon })
    else {
      return nil
    }

    let latOffset = latitude - Double(tileLat),
      lonOffset = longitude - Double(tileLon)

    return (entry, latOffset, lonOffset)
  }

  /// Reads a single elevation sample from disk at the given row and column.
  private func sample(row: Int, col: Int, in entry: TileIndexEntry) -> Int16? {
    let sampleIndex = row * resolution + col,
      byteOffset = Int(entry.dataOffset) + sampleIndex * 2

    guard byteOffset + 2 <= fileSize else { return nil }

    var value: Int16 = 0
    let bytesRead = pread(file.fd, &value, 2, off_t(byteOffset))
    guard bytesRead == 2 else { return nil }

    return value == Self.voidValue ? nil : value
  }

  /// Performs bilinear interpolation between four corner values.
  /// - Parameters:
  ///   - topLeft: Value at (row0, col0)
  ///   - topRight: Value at (row0, col1)
  ///   - bottomLeft: Value at (row1, col0)
  ///   - bottomRight: Value at (row1, col1)
  ///   - rowFrac: Fractional row position (0-1)
  ///   - colFrac: Fractional column position (0-1)
  /// - Returns: Interpolated value
  private func bilinearInterpolate(
    topLeft: Double,
    topRight: Double,
    bottomLeft: Double,
    bottomRight: Double,
    rowFrac: Double,
    colFrac: Double
  ) -> Double {
    let top = topLeft * (1 - colFrac) + topRight * colFrac,
      bottom = bottomLeft * (1 - colFrac) + bottomRight * colFrac
    return top * (1 - rowFrac) + bottom * rowFrac
  }

  // MARK: - Nested Types

  /// Tile index entry.
  private struct TileIndexEntry {
    let latitude: Int16
    let longitude: Int16
    /// Data offset from start of file
    let dataOffset: UInt64
    let dataLength: UInt32
  }

  /// Wraps a POSIX file descriptor with automatic close on deallocation.
  private final class FileDescriptorBox: Sendable {

    let fd: CInt

    init(_ fd: CInt) { self.fd = fd }
    deinit { Darwin.close(fd) }
  }
}
