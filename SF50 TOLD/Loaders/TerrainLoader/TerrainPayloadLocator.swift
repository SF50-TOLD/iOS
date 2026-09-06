import BackgroundAssets
import Foundation
import SF50_Shared
import System

/// Which store a terrain payload came from.
enum TerrainPayloadSource: Equatable, Sendable {

  // MARK: - Cases

  /// The shared container, written before the app moved terrain onto managed asset packs.
  ///
  /// Devices that already hold a region keep reading it from here, so nobody re-downloads
  /// gigabytes to gain nothing.
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
/// Terrain arrives as an asset pack the system manages, but a device upgrading from an earlier
/// build already holds its regions in the shared container. Both are valid sources, so every
/// reader goes through here rather than assuming one location.
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
  /// `url(for:)` answers with a path whether or not anything is behind it, so the file has to be
  /// checked for separately. Taking the URL as proof of installation reports every region as
  /// present, and each one then fails to load and is branded corrupt.
  ///
  /// `assetPackIsAvailableLocally(withID:)` would say this directly, but it needs iOS 26.4 and the
  /// app supports 26.0.
  private static func systemAssetPackURL(for region: TerrainRegion) -> URL? {
    guard let url = try? AssetPackManager.shared.url(for: FilePath(region.remoteFilename)),
      FileManager.default.fileExists(atPath: url.path)
    else { return nil }
    return url
  }

  // MARK: - Methods

  /// Reports what `region`'s payload amounts to.
  ///
  /// The shared container wins when it holds a complete payload: it is the copy the device
  /// already paid for, and preferring it is what keeps an upgrade from re-downloading a region.
  func state(of region: TerrainRegion) -> TerrainPayloadState {
    if inventory?.state(of: region) == .complete, let inventory {
      return .installed(inventory.localURL(for: region), source: .legacyContainer)
    }
    if let url = assetPackURL(region) {
      return .installed(url, source: .assetPack)
    }
    return requestedRegions.contains(region) ? .purged : .absent
  }
}
