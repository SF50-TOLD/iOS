import BackgroundAssets
import Foundation
import SF50_Shared
import System

/// Which store a terrain payload came from.
enum TerrainPayloadSource: Equatable, Sendable {

  // MARK: - Cases

  /// The shared container, written before the app moved terrain onto managed asset packs.
  ///
  /// A device that holds a region here keeps reading it until the region's pack is installed, so
  /// it is never left without terrain while the pack downloads.
  case legacyContainer

  /// An asset pack the system downloaded and manages.
  case assetPack
}

/// What a terrain region's payload amounts to right now.
enum TerrainPayloadState: Equatable, Sendable {

  // MARK: - Cases

  /// A payload is on disk and ready to load.
  case installed(URL, source: TerrainPayloadSource)

  /// The pilot asked for this region, but nothing is on disk.
  ///
  /// Asset packs are purgeable, so the system reclaims one when storage runs short — without
  /// telling the app. The only thing separating that from a region nobody ever asked for is the
  /// record of the request.
  case purged

  /// Nothing is on disk, and nobody asked for it.
  case absent

  // MARK: - Instance Properties

  /// The payload's location, if there is one to read.
  var url: URL? {
    guard case .installed(let url, _) = self else { return nil }
    return url
  }
}

/// Says where a terrain region's payload is, across both stores the app reads.
///
/// Terrain arrives as an asset pack the system manages, but a device upgrading from a build that
/// predates asset packs may still hold regions in the shared container. Every reader goes through
/// here rather than assuming one location.
struct TerrainPayloadLocator: Sendable {

  // MARK: - Instance Properties

  /// Reads the shared container, or `nil` when the app group is unreachable.
  private let inventory: TerrainRegionInventory?

  /// Regions the pilot has asked for, which is what makes a missing payload legible as purged.
  private let requestedRegions: Set<TerrainRegion>

  /// Resolves a region to its asset pack's payload, or `nil` when no pack is installed.
  private let assetPackURL: @Sendable (TerrainRegion) -> URL?

  // MARK: - Initializers

  init(
    inventory: TerrainRegionInventory?,
    requestedRegions: Set<TerrainRegion>,
    assetPackURL: @escaping @Sendable (TerrainRegion) -> URL?
  ) {
    self.inventory = inventory
    self.requestedRegions = requestedRegions
    self.assetPackURL = assetPackURL
  }

  /// Reads asset packs from the system's store.
  init(inventory: TerrainRegionInventory?, requestedRegions: Set<TerrainRegion>) {
    self.init(
      inventory: inventory,
      requestedRegions: requestedRegions,
      assetPackURL: Self.systemAssetPackURL
    )
  }

  // MARK: - Type Methods

  /// Where the system keeps `region`'s payload, if its pack is installed.
  ///
  /// `url(for:)` answers with a path whether or not anything is behind it, so installation is
  /// asked of the manager and the file is checked for as well: a pack the manager reports as
  /// local has been seen with its files missing.
  private static func systemAssetPackURL(for region: TerrainRegion) -> URL? {
    let manager = AssetPackManager.shared
    guard manager.assetPackIsAvailableLocally(withID: region.downloadIdentifier),
      let url = try? manager.url(for: FilePath(region.remoteFilename)),
      FileManager.default.fileExists(atPath: url.path)
    else { return nil }
    return url
  }

  // MARK: - Methods

  /// Reports what `region`'s payload amounts to.
  ///
  /// An installed pack wins: it is kept current by the system, while a copy in the shared
  /// container is whatever was published before the app adopted asset packs.
  func state(of region: TerrainRegion) -> TerrainPayloadState {
    if let url = assetPackURL(region) {
      return .installed(url, source: .assetPack)
    }
    if inventory?.state(of: region) == .complete, let inventory {
      return .installed(inventory.localURL(for: region), source: .legacyContainer)
    }
    return requestedRegions.contains(region) ? .purged : .absent
  }
}
