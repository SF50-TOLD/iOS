import Foundation
import Testing

@testable import SF50_Shared

/// Reads hand-built terrain files, so a byte read at the wrong offset, width, sign or byte order
/// shows up as a wrong elevation. Version 2 stores samples uncompressed and reads them straight off
/// disk; version 3 compresses each tile with LZFSE and reads samples from the decompressed tile.
@Suite
struct `Terrain file reading` {

  @Test(arguments: [TerrainFileFixture.Version.uncompressed, .compressed])
  func `reads the sample at a coordinate`(version: TerrainFileFixture.Version) throws {
    let tile = try TerrainFileFixture.write(version: version)
    defer { tile.remove() }

    #expect(tile.reader.elevation(at: 37.99, longitude: -121.99) == 100)
    #expect(tile.reader.elevation(at: 37.5, longitude: -121.5) == 500)
    #expect(tile.reader.elevation(at: 37.99, longitude: -121.0) == -5)
  }

  @Test(arguments: [TerrainFileFixture.Version.uncompressed, .compressed])
  func `reports no elevation for a void sample or a missing tile`(
    version: TerrainFileFixture.Version
  ) throws {
    let tile = try TerrainFileFixture.write(version: version)
    defer { tile.remove() }

    #expect(tile.reader.elevation(at: 37.0, longitude: -121.0) == nil)
    #expect(tile.reader.elevation(at: 40.5, longitude: -121.5) == nil)
  }

  @Test(arguments: [TerrainFileFixture.Version.uncompressed, .compressed])
  func `interpolates between the four surrounding samples`(
    version: TerrainFileFixture.Version
  ) throws {
    let tile = try TerrainFileFixture.write(version: version)
    defer { tile.remove() }

    let elevation = try #require(tile.reader.interpolatedElevation(at: 37.75, longitude: -121.75))
    #expect(elevation == 300)
  }
}

/// A one-tile terrain file covering 37°N–38°N, 122°W–121°W at three samples per side.
struct TerrainFileFixture {
  /// Rows run north to south, columns west to east.
  private static let samples: [Int16] = [
    100, 200, -5,
    400, 500, 600,
    700, 800, .min
  ]
  private static let resolution: UInt16 = 3,
    tileLatitude: Int16 = 37,
    tileLongitude: Int16 = -122,
    headerSize = 20

  let url: URL, reader: MappedTerrainTile

  static func write(version: Version) throws -> Self {
    let url = FileManager.default.temporaryDirectory
      .appending(path: "MappedTerrainTileTests-\(UUID().uuidString).srtm")
    try fileData(version: version).write(to: url)
    return .init(url: url, reader: try MappedTerrainTile(fileURL: url))
  }

  private static func fileData(version: Version) throws -> Data {
    var tileData = Data()
    tileData.append(contentsOf: samples, .littleEndian)
    var storedTile = tileData
    if version == .compressed {
      // swiftlint:disable:next legacy_objc_type
      storedTile = try (tileData as NSData).compressed(using: .lzfse) as Data
    }
    let indexEntrySize = version == .compressed ? 20 : 16

    var file = Data("SRTM".utf8)
    file.append(version.rawValue, .littleEndian)
    file.append(resolution, .littleEndian)
    file.append(UInt32(1), .littleEndian)
    for bound in [tileLatitude, tileLatitude + 1, tileLongitude, tileLongitude + 1] {
      file.append(bound, .littleEndian)
    }

    file.append(tileLatitude, .littleEndian)
    file.append(tileLongitude, .littleEndian)
    file.append(UInt64(headerSize + indexEntrySize), .littleEndian)
    file.append(UInt32(storedTile.count), .littleEndian)
    if version == .compressed { file.append(UInt32(tileData.count), .littleEndian) }

    file.append(storedTile)
    return file
  }

  func remove() {
    try? FileManager.default.removeItem(at: url)
  }

  enum Version: UInt16 {
    case uncompressed = 2
    case compressed = 3
  }
}
