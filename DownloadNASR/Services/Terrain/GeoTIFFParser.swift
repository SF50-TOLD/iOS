import Foundation

/// Errors that can occur during GeoTIFF parsing.
enum GeoTIFFParserError: LocalizedError {
  case unsupportedLayout(String)
  case truncated
  case decompressionFailed(any Error)

  var errorDescription: String? {
    String(localized: "Failed to process GeoTIFF data.")
  }

  var failureReason: String? {
    switch self {
      case .unsupportedLayout(let detail):
        String(localized: "The GeoTIFF is not laid out as a Copernicus DEM tile: \(detail)")
      case .truncated:
        String(localized: "The GeoTIFF ends before the data it describes.")
      case .decompressionFailed(let error):
        String(localized: "A GeoTIFF tile could not be decompressed: \(error.localizedDescription)")
    }
  }
}

/// Decodes the Cloud-Optimized GeoTIFFs the Copernicus DEM is published as.
///
/// Every Copernicus tile shares one layout, and this reads exactly that layout, rejecting
/// anything else: a classic little-endian TIFF whose first image is a single band of 32-bit
/// floats, cut into square tiles, each DEFLATE-compressed with the floating-point predictor.
/// Decoding that directly, rather than through a general TIFF library that boxes every sample,
/// is what makes rebuilding every region practical.
enum GeoTIFFParser {

  // MARK: - Type Properties

  /// Length of the zlib header before each tile's DEFLATE stream.
  private static let zlibHeaderLength = 2

  // MARK: - Type Methods

  /// Parses a GeoTIFF file and extracts its elevations.
  /// - Parameter url: URL to the GeoTIFF file
  /// - Returns: The tile's elevations in meters, rounded to `Int16`
  static func parse(contentsOf url: URL) throws -> Elevations {
    try parse(data: Data(contentsOf: url, options: .alwaysMapped))
  }

  /// Parses GeoTIFF data and extracts its elevations.
  /// - Parameter data: Raw GeoTIFF file data
  /// - Returns: The tile's elevations in meters, rounded to `Int16`
  static func parse(data: Data) throws -> Elevations {
    let layout = try Layout(data: data)
    var elevations = Elevations(width: layout.width, height: layout.height)

    for (tileIndex, byteRange) in layout.tileByteRanges.enumerated() {
      guard byteRange.upperBound <= data.count else { throw GeoTIFFParserError.truncated }
      let samples = try inflate(data[byteRange], expectedCount: layout.bytesPerTile)
      layout.decodeTile(samples, at: tileIndex, into: &elevations)
    }

    return elevations
  }

  /// Inflates one tile's zlib-wrapped DEFLATE stream.
  private static func inflate(_ compressed: Data, expectedCount: Int) throws -> [UInt8] {
    let deflateStream = Data(compressed.dropFirst(zlibHeaderLength))
    let inflated: Data
    do {
      // swiftlint:disable:next legacy_objc_type
      inflated = try (deflateStream as NSData).decompressed(using: .zlib) as Data
    } catch {
      throw GeoTIFFParserError.decompressionFailed(error)
    }
    guard inflated.count == expectedCount else { throw GeoTIFFParserError.truncated }
    return [UInt8](inflated)
  }

  // MARK: - Nested Types

  /// Where a Copernicus GeoTIFF keeps its full-resolution image, read from its first IFD.
  private struct Layout {

    // MARK: - Type Properties

    /// The values each tag must hold for the layout to be one this decodes.
    private static let requiredValues: [Tag: Set<Int>] = [
      .bitsPerSample: [32],
      .compression: [8, 32_946],  // DEFLATE, in its standard and its Adobe numbering
      .samplesPerPixel: [1],
      .predictor: [3],  // floating point
      .sampleFormat: [3]  // IEEE float
    ]

    /// Byte-order mark of a little-endian TIFF, "II".
    private static let littleEndianMark: UInt16 = 0x4949

    /// Version number of a classic, 32-bit-offset TIFF.
    private static let classicTIFFVersion: UInt16 = 42

    /// Length of one image file directory entry: tag, type, count and value or offset.
    private static let directoryEntryLength = 12

    /// TIFF field types that hold integers, by type code: SHORT and LONG.
    private static let byteWidths: [UInt16: Int] = [3: 2, 4: 4]

    // MARK: - Instance Properties

    let width: Int, height: Int
    let tileWidth: Int, tileHeight: Int
    let tileByteRanges: [Range<Int>]

    /// Size of one inflated tile: every sample of a full tile, including padding past the image.
    var bytesPerTile: Int { tileWidth * tileHeight * MemoryLayout<Float32>.size }

    private var tilesAcross: Int { (width + tileWidth - 1) / tileWidth }

    // MARK: - Initializers

    init(data: Data) throws {
      let bytes = data.bytes
      guard bytes.byteCount >= 8,
        bytes.load(fromByteOffset: 0, as: UInt16.self, .littleEndian) == Self.littleEndianMark,
        bytes.load(fromByteOffset: 2, as: UInt16.self, .littleEndian) == Self.classicTIFFVersion
      else {
        throw GeoTIFFParserError.unsupportedLayout("not a classic little-endian TIFF")
      }

      let fields = try Self.readFirstDirectory(of: data)
      func value(_ tag: Tag) throws -> Int {
        guard let value = fields[tag]?.first else {
          throw GeoTIFFParserError.unsupportedLayout("no tag \(tag.rawValue)")
        }
        return value
      }

      for (tag, allowed) in Self.requiredValues where try !allowed.contains(value(tag)) {
        throw GeoTIFFParserError.unsupportedLayout("tag \(tag.rawValue) is \(try value(tag))")
      }

      width = try value(.imageWidth)
      height = try value(.imageLength)
      tileWidth = try value(.tileWidth)
      tileHeight = try value(.tileLength)

      let offsets = fields[.tileOffsets] ?? [],
        byteCounts = fields[.tileByteCounts] ?? [],
        tilesDown = (height + tileHeight - 1) / tileHeight
      guard offsets.count == byteCounts.count,
        offsets.count == tilesDown * ((width + tileWidth - 1) / tileWidth)
      else {
        throw GeoTIFFParserError.unsupportedLayout("tile index does not cover the image")
      }
      tileByteRanges = zip(offsets, byteCounts).map { $0..<($0 + $1) }
    }

    // MARK: - Type Methods

    /// Reads the integer-valued fields of the first image file directory.
    private static func readFirstDirectory(of data: Data) throws -> [Tag: [Int]] {
      let bytes = data.bytes
      func uint16(at offset: Int) throws -> Int {
        guard offset + 2 <= bytes.byteCount else { throw GeoTIFFParserError.truncated }
        return Int(bytes.load(fromByteOffset: offset, as: UInt16.self, .littleEndian))
      }
      func uint32(at offset: Int) throws -> Int {
        guard offset + 4 <= bytes.byteCount else { throw GeoTIFFParserError.truncated }
        return Int(bytes.load(fromByteOffset: offset, as: UInt32.self, .littleEndian))
      }

      let directoryOffset = try uint32(at: 4),
        entryCount = try uint16(at: directoryOffset)
      var fields: [Tag: [Int]] = [:]

      for entry in 0..<entryCount {
        let entryOffset = directoryOffset + 2 + entry * directoryEntryLength
        guard let tag = Tag(rawValue: UInt16(try uint16(at: entryOffset))),
          let width = byteWidths[UInt16(try uint16(at: entryOffset + 2))]
        else { continue }

        let count = try uint32(at: entryOffset + 4)
        // Values that fit in the entry's four value bytes are stored there; others elsewhere.
        let valuesOffset = count * width <= 4 ? entryOffset + 8 : try uint32(at: entryOffset + 8)
        fields[tag] = try (0..<count).map { index in
          let offset = valuesOffset + index * width
          return width == 2 ? try uint16(at: offset) : try uint32(at: offset)
        }
      }

      return fields
    }

    /// Rounds a sample to whole meters, or marks it void when it is not a finite elevation.
    private static func elevation(_ sample: Float32) -> Int16 {
      guard sample.isFinite, sample > Float32(Int16.min), sample <= Float32(Int16.max) else {
        return Elevations.voidValue
      }
      return Int16(sample.rounded())
    }

    // MARK: - Instance Methods

    /// Undoes the floating-point predictor on an inflated tile and writes its samples, rounded to
    /// whole meters, into `elevations`. Samples in the tile's padding past the image are dropped.
    ///
    /// The predictor stores each row as four byte planes, most significant first, then
    /// difference-codes the row's bytes left to right; decoding runs a cumulative sum across the
    /// row and reassembles each float from its four planes.
    func decodeTile(_ tile: [UInt8], at tileIndex: Int, into elevations: inout Elevations) {
      var tile = tile
      let originRow = (tileIndex / tilesAcross) * tileHeight,
        originColumn = (tileIndex % tilesAcross) * tileWidth,
        visibleRows = min(tileHeight, height - originRow),
        visibleColumns = min(tileWidth, width - originColumn),
        rowBytes = tileWidth * MemoryLayout<Float32>.size

      for row in 0..<visibleRows {
        let rowStart = row * rowBytes
        for byte in (rowStart + 1)..<(rowStart + rowBytes) {
          tile[byte] &+= tile[byte - 1]
        }
        for column in 0..<visibleColumns {
          let planeStart = rowStart + column,
            bits =
              UInt32(tile[planeStart]) << 24
              | UInt32(tile[planeStart + tileWidth]) << 16
              | UInt32(tile[planeStart + 2 * tileWidth]) << 8
              | UInt32(tile[planeStart + 3 * tileWidth])
          elevations[originRow + row, originColumn + column] =
            Self.elevation(Float32(bitPattern: bits))
        }
      }
    }

    // MARK: - Nested Types

    /// The TIFF tags this layout reads.
    private enum Tag: UInt16 {
      case imageWidth = 256
      case imageLength = 257
      case bitsPerSample = 258
      case compression = 259
      case samplesPerPixel = 277
      case predictor = 317
      case tileWidth = 322
      case tileLength = 323
      case tileOffsets = 324
      case tileByteCounts = 325
      case sampleFormat = 339
    }
  }
}
