import BackgroundAssets
import ExtensionFoundation
import Foundation
import SF50_Shared
import os

/// Decides which terrain asset packs the system downloads on the app's behalf.
///
/// Every region is published with a `prefetch` download policy, so the system offers all eleven
/// after an install or update and this is what narrows them to one. Terrain runs to gigabytes per
/// region and only one region is ever under the aircraft, so fetching them all would be absurd.
///
/// Everything else the download takes — the transfer, its retries, decompressing the archive, and
/// storing the result — belongs to the system under managed asset packs. That is the whole reason
/// this type is three lines instead of a hundred and forty.
@main
struct TerrainDownloaderExtension: ManagedDownloaderExtension {

  // MARK: - Instance Properties

  private let logger = Logger(subsystem: "codes.tim.SF50-TOLD", category: "TerrainAssets")

  // MARK: - Other Methods

  func shouldDownload(_ assetPack: AssetPack) -> Bool {
    let region = TerrainRegion.localePrefetchRegion
    let wanted = assetPack.id == region.downloadIdentifier

    logger.notice(
      """
      Asset pack \(assetPack.id, privacy: .public) offered; prefetch region is \
      \(region.rawValue, privacy: .public) — \
      \(wanted ? "downloading" : "skipping", privacy: .public)
      """
    )
    return wanted
  }
}
