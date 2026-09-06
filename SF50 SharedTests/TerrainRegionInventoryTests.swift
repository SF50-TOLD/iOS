import Foundation
import Testing

@testable import SF50_Shared

/// The inventory is the single authority on what a region's files mean, and the reason it exists is
/// that file existence alone can't tell a finished download from one still being written. A partial
/// file that reads as finished gets handed to `TerrainService`, fails to parse, and is branded
/// corrupt — so the size comparison below is the whole point of the type.
struct TerrainRegionInventoryTests {

  // MARK: - Type Properties

  private static let expectedBytes = 1024

  private static let manifestJSON = """
    {
      "baseURL" : "https://example.invalid/terrain/",
      "generatedAt" : "2026-02-18T11:31:38Z",
      "version" : 3,
      "regions" : [
        {
          "filename" : "terrain-ma.srtm",
          "id" : "ma",
          "sizeBytes" : 1024
        }
      ]
    }
    """

  // MARK: - Other Methods

  @Test
  func `file matching the manifest size is complete`() throws {
    let directory = try makeDirectory()
    try write(byteCount: Self.expectedBytes, to: directory, named: "ma.srtm")

    let inventory = try makeInventory(in: directory)
    #expect(inventory.state(of: .midAtlantic) == .complete)
  }

  /// A download still in flight is short, not broken. Reporting it as anything but incomplete is
  /// what produces a spurious “corrupted” badge on a region that is merely unfinished.
  @Test
  func `file shorter than the manifest size is incomplete`() throws {
    let directory = try makeDirectory()
    try write(byteCount: Self.expectedBytes / 2, to: directory, named: "ma.srtm")

    let inventory = try makeInventory(in: directory)
    #expect(
      inventory.state(of: .midAtlantic)
        == .incomplete(bytesOnDisk: Self.expectedBytes / 2, expectedBytes: Self.expectedBytes)
    )
  }

  @Test
  func `missing file is absent`() throws {
    let inventory = try makeInventory(in: try makeDirectory())
    #expect(inventory.state(of: .midAtlantic) == .absent)
  }

  /// Nothing expands v2-era payloads any more, so a leftover has to read as absent — otherwise the
  /// region looks like it holds something usable and never offers to download.
  @Test
  func `a leftover compressed payload reads as absent`() throws {
    let directory = try makeDirectory()
    try write(byteCount: Self.expectedBytes, to: directory, named: "terrain-ma.srtm.lzma")

    let inventory = try makeInventory(in: directory)
    #expect(inventory.state(of: .midAtlantic) == .absent)
  }

  /// A leftover runs to gigabytes the app can neither use nor offer to delete, so finding one has
  /// to reclaim it. Reporting whether it found one is what lets the caller say so.
  @Test
  func `a leftover compressed payload is reclaimed once`() throws {
    let directory = try makeDirectory()
    try write(byteCount: Self.expectedBytes, to: directory, named: "terrain-ma.srtm.lzma")
    let inventory = try makeInventory(in: directory)

    #expect(inventory.removeLegacyCompressedPayload(for: .midAtlantic))
    #expect(
      !FileManager.default.fileExists(
        atPath: directory.appendingPathComponent("terrain-ma.srtm.lzma").path
      )
    )
    #expect(!inventory.removeLegacyCompressedPayload(for: .midAtlantic))
  }

  /// Reclaiming must not touch the payload the region actually uses.
  @Test
  func `reclaiming a leftover leaves a ready payload alone`() throws {
    let directory = try makeDirectory()
    try write(byteCount: Self.expectedBytes, to: directory, named: "ma.srtm")
    let inventory = try makeInventory(in: directory)

    #expect(!inventory.removeLegacyCompressedPayload(for: .midAtlantic))
    #expect(inventory.state(of: .midAtlantic) == .complete)
  }

  /// A region the manifest says nothing about can't be size-checked, so it can never be complete.
  @Test
  func `region missing from the manifest is absent`() throws {
    let directory = try makeDirectory()
    try write(byteCount: Self.expectedBytes, to: directory, named: "na.srtm")

    let inventory = try makeInventory(in: directory)
    #expect(inventory.state(of: .northAmerica) == .absent)
  }

  /// Both the app and its Background Assets extension store finished downloads, and which one gets
  /// the callback depends on whether the app happens to be running, so they have to agree on where
  /// a payload lands and both have to cope with one already being there.
  @Test
  func `storing a payload replaces whatever was there`() throws {
    let directory = try makeDirectory()
    try write(byteCount: 1, to: directory, named: "ma.srtm")
    let downloaded = try makeDirectory().appendingPathComponent("downloaded")
    try Data(repeating: 0, count: Self.expectedBytes).write(to: downloaded)

    let inventory = try makeInventory(in: directory)
    try inventory.store(downloaded, for: .midAtlantic)

    #expect(inventory.state(of: .midAtlantic) == .complete)
    #expect(!FileManager.default.fileExists(atPath: downloaded.path))
  }

  /// Storing is a question of where a file goes, not of how big it should be, and the Background
  /// Assets extension has to answer it from a bundle holding no manifest at all. Requiring one to
  /// store would make the extension crash on the very callback that saves the download.
  @Test
  func `storing a payload needs no manifest`() throws {
    let directory = try makeDirectory()
    let downloaded = try makeDirectory().appendingPathComponent("downloaded")
    try Data(repeating: 0, count: Self.expectedBytes).write(to: downloaded)

    try TerrainRegionInventory.store(downloaded, for: .midAtlantic, in: directory)

    let stored = directory.appendingPathComponent("ma.srtm")
    #expect(try stored.resourceValues(forKeys: [.fileSizeKey]).fileSize == Self.expectedBytes)
  }

  /// Nothing guarantees the terrain directory exists the first time a download finishes.
  @Test
  func `storing a payload creates the terrain directory`() throws {
    let directory = try makeDirectory().appendingPathComponent("Terrain", isDirectory: true)
    let downloaded = try makeDirectory().appendingPathComponent("downloaded")
    try Data(repeating: 0, count: Self.expectedBytes).write(to: downloaded)

    let inventory = try makeInventory(in: directory)
    try inventory.store(downloaded, for: .midAtlantic)

    #expect(inventory.state(of: .midAtlantic) == .complete)
  }

  /// A download cut short leaves a payload shorter than the manifest. Unless that state asks to be
  /// fetched again, the region is stuck: too short to use, and never retried because something is
  /// already there.
  @Test
  func `an unfinished payload asks to be fetched again`() {
    #expect(TerrainRegionFileState.incomplete(bytesOnDisk: 512, expectedBytes: 1024).needsDownload)
    #expect(TerrainRegionFileState.absent.needsDownload)
    #expect(!TerrainRegionFileState.complete.needsDownload)
  }

  // MARK: - Fixtures

  private func makeInventory(in directory: URL) throws -> TerrainRegionInventory {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let manifest = try decoder.decode(
      TerrainManifest.self,
      from: Data(Self.manifestJSON.utf8)
    )
    return .init(directory: directory, manifest: manifest)
  }

  private func makeDirectory() throws -> URL {
    let directory = URL.temporaryDirectory.appendingPathComponent(
      "terrain-inventory-\(UUID().uuidString)",
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }

  private func write(byteCount: Int, to directory: URL, named name: String) throws {
    try Data(repeating: 0, count: byteCount)
      .write(to: directory.appendingPathComponent(name))
  }
}
