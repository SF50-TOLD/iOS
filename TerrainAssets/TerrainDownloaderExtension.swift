import BackgroundAssets
import ExtensionFoundation
import Foundation
import SF50_Shared
import os

/// Decides which asset packs the system downloads on the app's behalf.
///
/// Every terrain region is published with a `prefetch` download policy, so the system offers all
/// eleven after an install or update and this is what narrows them. Terrain runs to gigabytes per
/// region, so the system fetches the region matching the device's locale, and the regions the pilot
/// has already downloaded. Declining a region the pilot has would leave its old version to be
/// dropped when a new one is published, with nothing fetched in its place.
///
/// The NOTAM model is prefetched too, unless the pilot deleted it or the device lacks room for it
/// (`NOTAMModelPack.shouldPrefetch(isDeclined:availableCapacity:downloadSize:)`).
///
/// Everything else the download takes — the transfer, its retries, decompressing the archive, and
/// storing the result — belongs to the system under managed asset packs, which is why this type
/// only answers yes or no.
@main
struct TerrainDownloaderExtension: ManagedDownloaderExtension {

  // MARK: - Instance Properties

  private let logger = Logger(subsystem: "codes.tim.SF50-TOLD", category: "TerrainAssets")

  // MARK: - Other Methods

  func shouldDownload(_ assetPack: AssetPack) -> Bool {
    assetPack.id == NOTAMModelPack.id
      ? shouldDownloadNOTAMModel(assetPack) : shouldDownloadTerrain(assetPack)
  }

  private func shouldDownloadNOTAMModel(_ assetPack: AssetPack) -> Bool {
    let wanted = NOTAMModelPack.shouldPrefetch(
      isDeclined: NOTAMModelPack.isDeclined,
      availableCapacity: NOTAMModelPack.availableCapacity(),
      downloadSize: assetPack.downloadSize
    )
    logger.notice(
      "NOTAM model offered — \(wanted ? "downloading" : "skipping", privacy: .public)"
    )
    return wanted
  }

  private func shouldDownloadTerrain(_ assetPack: AssetPack) -> Bool {
    let wantedRegions = TerrainRegion.requested.union([TerrainRegion.localePrefetchRegion]),
      wanted = wantedRegions.contains { $0.downloadIdentifier == assetPack.id }

    logger.notice(
      """
      Asset pack \(assetPack.id, privacy: .public) offered; wanted regions are \
      \(wantedRegions.map(\.rawValue).sorted(), privacy: .public) — \
      \(wanted ? "downloading" : "skipping", privacy: .public)
      """
    )
    return wanted
  }
}
