import Foundation
import SF50_Shared
import Testing

@testable import SF50_TOLD

/// Terrain now lives in two places: the shared container a device filled before the app adopted
/// managed asset packs, and the system's asset-pack store. The locator is what reconciles them, and
/// the distinction it exists to draw is between a region the system reclaimed for space and one
/// nobody ever asked for — those look identical on disk, and only one of them should tell the pilot
/// something went missing.
struct TerrainPayloadLocatorTests {

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

  // MARK: - Methods

  /// A device upgrading from an earlier build already holds its regions. Reading them where they
  /// sit is the whole reason nobody re-downloads up to 9 GB.
  @Test
  func `a complete payload in the shared container is installed`() throws {
    let directory = try makeDirectory()
    try write(byteCount: Self.expectedBytes, to: directory, named: "ma.srtm")
    let locator = try makeLocator(in: directory, requesting: [], assetPacks: [:])

    #expect(
      locator.state(of: .midAtlantic)
        == .installed(directory.appendingPathComponent("ma.srtm"), source: .legacyContainer)
    )
  }

  /// The container wins when both hold the region, so an upgrade keeps reading the copy the device
  /// already paid for rather than the pack it would have to fetch.
  @Test
  func `the shared container outranks an asset pack`() throws {
    let directory = try makeDirectory()
    try write(byteCount: Self.expectedBytes, to: directory, named: "ma.srtm")
    let packURL = URL(filePath: "/packs/terrain-ma.srtm")
    let locator = try makeLocator(
      in: directory,
      requesting: [.midAtlantic],
      assetPacks: [.midAtlantic: packURL]
    )

    #expect(locator.state(of: .midAtlantic).url == directory.appendingPathComponent("ma.srtm"))
  }

  /// With nothing in the container, the pack is the payload.
  @Test
  func `an installed asset pack is installed`() throws {
    let packURL = URL(filePath: "/packs/terrain-ma.srtm")
    let locator = try makeLocator(
      in: try makeDirectory(),
      requesting: [.midAtlantic],
      assetPacks: [.midAtlantic: packURL]
    )

    #expect(locator.state(of: .midAtlantic) == .installed(packURL, source: .assetPack))
  }

  /// The distinction the type exists for: a requested region with nothing on disk was reclaimed by
  /// the system, and saying so is what lets the app tell the pilot rather than silently showing the
  /// region as never downloaded.
  @Test
  func `a requested region with no payload reads as purged`() throws {
    let locator = try makeLocator(
      in: try makeDirectory(),
      requesting: [.midAtlantic],
      assetPacks: [:]
    )

    #expect(locator.state(of: .midAtlantic) == .purged)
  }

  /// The same empty disk, without a request behind it, is just a region nobody downloaded. Reading
  /// this as purged would alarm every pilot about terrain they never asked for.
  @Test
  func `an unrequested region with no payload reads as absent`() throws {
    let locator = try makeLocator(
      in: try makeDirectory(),
      requesting: [],
      assetPacks: [:]
    )

    #expect(locator.state(of: .midAtlantic) == .absent)
  }

  /// A payload shorter than the manifest can't be loaded, so it must not read as installed — but a
  /// half-written file is not a purge either.
  @Test
  func `a short payload does not read as installed`() throws {
    let directory = try makeDirectory()
    try write(byteCount: Self.expectedBytes / 2, to: directory, named: "ma.srtm")
    let locator = try makeLocator(in: directory, requesting: [.midAtlantic], assetPacks: [:])

    #expect(locator.state(of: .midAtlantic) == .purged)
  }

  // MARK: - Fixtures

  private func makeLocator(
    in directory: URL,
    requesting requestedRegions: Set<TerrainRegion>,
    assetPacks: [TerrainRegion: URL]
  ) throws -> TerrainPayloadLocator {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let manifest = try decoder.decode(TerrainManifest.self, from: Data(Self.manifestJSON.utf8))

    return .init(
      inventory: .init(directory: directory, manifest: manifest),
      requestedRegions: requestedRegions,
      assetPackURL: { assetPacks[$0] }
    )
  }

  private func makeDirectory() throws -> URL {
    let directory = URL.temporaryDirectory.appendingPathComponent(
      "terrain-locator-\(UUID().uuidString)",
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
