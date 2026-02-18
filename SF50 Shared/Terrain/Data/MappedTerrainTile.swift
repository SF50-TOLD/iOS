import Compression
import Foundation
import os

/// Provides O(1) coordinate-to-elevation lookups from a terrain data file.
///
/// The terrain file is opened once at initialization and individual elevation
/// samples are read on demand via `pread`. Only the header and tile index
/// (~100 KB) are held in memory — the multi-gigabyte elevation data stays on
/// disk, avoiding virtual-memory limits on iOS.
///
/// For v3 files, tile data is LZFSE-compressed on disk. Tiles are decompressed
/// on demand into a small LRU cache (~30 MB / 10 tiles).
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
/// Tile index:
///   v1 (12 bytes per tile): lat + lon + offset:UInt32 + length:UInt32
///   v2 (16 bytes per tile): lat + lon + offset:UInt64 + length:UInt32
///   v3 (20 bytes per tile): lat + lon + offset:UInt64 + compressedLength:UInt32
///                           + uncompressedLength:UInt32
///
/// Tile data:
///   v1/v2: Raw Int16 elevations, row-major from north to south
///   v3: LZFSE-compressed Int16 elevations (0 bytes for void tiles)
/// ```
final class MappedTerrainTile: Sendable {

  // MARK: - Type Properties

  /// SRTM void/no-data sentinel value.
  private static let voidValue: Int16 = -32768

  /// Maximum number of decompressed tiles to hold in cache (~30 MB at SRTM3).
  private static let maxCachedTiles = 10

  /// Logger for debug output.
  private static let logger = Logger(
    subsystem: "codes.tim.SF50-TOLD",
    category: "MappedTerrainTile"
  )

  // MARK: - Instance Properties

  /// File format version.
  private let version: UInt16

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

  /// LRU cache for decompressed v3 tile data.
  private let tileCache: OSAllocatedUnfairLock<TileCache>

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
    guard let version = try? reader.readUInt16(),
      version >= 1 && version <= 3
    else {
      throw TerrainServiceError.invalidFile(fileURL)
    }
    self.version = version

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
    // Version 3: 20 bytes per entry (lat:2 + lon:2 + offset:8 + compressedLength:4 + uncompressedLength:4)
    let entrySize: Int
    switch version {
      case 1: entrySize = 12
      case 2: entrySize = 16
      default: entrySize = 20
    }
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
      let compressedLength: UInt32
      let uncompressedLength: UInt32

      switch version {
        case 1:
          dataOffset = try UInt64(indexReader.readUInt32())
          compressedLength = try indexReader.readUInt32()
          uncompressedLength = compressedLength
        case 2:
          dataOffset = try indexReader.readUInt64()
          compressedLength = try indexReader.readUInt32()
          uncompressedLength = compressedLength
        default:
          dataOffset = try indexReader.readUInt64()
          compressedLength = try indexReader.readUInt32()
          uncompressedLength = try indexReader.readUInt32()
      }

      index.append(
        .init(
          latitude: lat,
          longitude: lon,
          dataOffset: dataOffset,
          compressedLength: compressedLength,
          uncompressedLength: uncompressedLength
        )
      )
    }

    self.tileIndex = index
    self.tileCache = OSAllocatedUnfairLock(initialState: TileCache())

    Self.logger.info(
      "Opened \(fileURL.lastPathComponent): v\(version), \(self.tileCount) tiles, resolution \(self.resolution), \(self.fileSize) bytes"
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

  /// Reads a single elevation sample from the given tile.
  private func sample(row: Int, col: Int, in entry: TileIndexEntry) -> Int16? {
    if version < 3 {
      return sampleDirect(row: row, col: col, in: entry)
    }
    return sampleCompressed(row: row, col: col, in: entry)
  }

  /// Reads a single sample directly from uncompressed tile data on disk (v1/v2).
  private func sampleDirect(row: Int, col: Int, in entry: TileIndexEntry) -> Int16? {
    let sampleIndex = row * resolution + col,
      byteOffset = Int(entry.dataOffset) + sampleIndex * 2

    guard byteOffset + 2 <= fileSize else { return nil }

    var value: Int16 = 0
    let bytesRead = pread(file.fd, &value, 2, off_t(byteOffset))
    guard bytesRead == 2 else { return nil }

    return value == Self.voidValue ? nil : value
  }

  /// Reads a single sample from compressed tile data (v3), using the LRU cache.
  private func sampleCompressed(row: Int, col: Int, in entry: TileIndexEntry) -> Int16? {
    // Void tile optimization: both lengths zero means all-void
    if entry.compressedLength == 0 && entry.uncompressedLength == 0 {
      return nil
    }

    let key = TileKey(latitude: entry.latitude, longitude: entry.longitude)

    // Check cache
    if let data = tileCache.withLock({ cache -> Data? in
      if var cached = cache.tiles[key] {
        cache.accessCounter &+= 1
        cached.lastAccess = cache.accessCounter
        cache.tiles[key] = cached
        return cached.data
      }
      return nil
    }) {
      return readSample(from: data, row: row, col: col)
    }

    // Cache miss — decompress tile from disk
    guard let decompressed = decompressTile(entry) else { return nil }

    // Store in cache, evicting LRU if full
    tileCache.withLock { cache in
      if cache.tiles.count >= Self.maxCachedTiles {
        if let lruKey = cache.tiles.min(by: { $0.value.lastAccess < $1.value.lastAccess })?.key {
          cache.tiles.removeValue(forKey: lruKey)
        }
      }
      cache.accessCounter &+= 1
      cache.tiles[key] = CachedTile(data: decompressed, lastAccess: cache.accessCounter)
    }

    return readSample(from: decompressed, row: row, col: col)
  }

  /// Reads a single Int16 sample from decompressed tile data.
  private func readSample(from data: Data, row: Int, col: Int) -> Int16? {
    let byteOffset = (row * resolution + col) * 2
    guard byteOffset + 2 <= data.count else { return nil }

    let value = data.withUnsafeBytes { buffer in
      buffer.load(fromByteOffset: byteOffset, as: Int16.self)
    }
    return value == Self.voidValue ? nil : value
  }

  /// Decompresses an LZFSE-compressed tile from disk.
  private func decompressTile(_ entry: TileIndexEntry) -> Data? {
    let compressedSize = Int(entry.compressedLength),
      uncompressedSize = Int(entry.uncompressedLength)

    guard compressedSize > 0, uncompressedSize > 0 else { return nil }

    // Read compressed data from disk
    guard
      let compressedData = Self.preadData(
        fd: file.fd,
        count: compressedSize,
        offset: off_t(entry.dataOffset)
      )
    else {
      Self.logger.error(
        "Failed to read compressed tile at \(entry.latitude),\(entry.longitude)"
      )
      return nil
    }

    // Decompress with LZFSE
    var decompressedBuffer = [UInt8](repeating: 0, count: uncompressedSize)
    let decompressedSize = compressedData.withUnsafeBytes { srcBuffer in
      guard let srcPointer = srcBuffer.baseAddress else { return 0 }
      return compression_decode_buffer(
        &decompressedBuffer,
        uncompressedSize,
        srcPointer.assumingMemoryBound(to: UInt8.self),
        compressedSize,
        nil,
        COMPRESSION_LZFSE
      )
    }

    guard decompressedSize == uncompressedSize else {
      Self.logger.error(
        "LZFSE decompression failed for tile \(entry.latitude),\(entry.longitude): expected \(uncompressedSize), got \(decompressedSize)"
      )
      return nil
    }

    return Data(decompressedBuffer)
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
    /// Data offset from start of file.
    let dataOffset: UInt64
    /// Compressed data length in bytes (equals uncompressed length for v1/v2).
    let compressedLength: UInt32
    /// Uncompressed data length in bytes.
    let uncompressedLength: UInt32
  }

  /// Cache key for decompressed tiles.
  private struct TileKey: Hashable {
    let latitude: Int16
    let longitude: Int16
  }

  /// A cached decompressed tile with LRU tracking.
  private struct CachedTile {
    let data: Data
    var lastAccess: UInt64
  }

  /// Thread-safe LRU cache state for decompressed tiles.
  private struct TileCache {
    var tiles: [TileKey: CachedTile] = [:]
    var accessCounter: UInt64 = 0
  }

  /// Wraps a POSIX file descriptor with automatic close on deallocation.
  private final class FileDescriptorBox: Sendable {

    let fd: CInt

    init(_ fd: CInt) { self.fd = fd }
    deinit { Darwin.close(fd) }
  }
}
