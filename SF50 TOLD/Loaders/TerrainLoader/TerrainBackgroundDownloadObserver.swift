import BackgroundAssets
import Foundation
import SF50_Shared
import os

/// Watches the system's terrain downloads on the app's behalf.
///
/// Background Assets delivers a finished download to whichever side is listening: the app's
/// `BADownloadManager` delegate when one is set, and the Background Assets extension otherwise.
/// Setting a delegate to observe progress therefore takes completion away from the extension, so
/// this stores finished payloads itself rather than only reporting on them.
final class TerrainBackgroundDownloadObserver: NSObject, BADownloadManagerDelegate {

  // MARK: - Instance Properties

  private let logger = Logger(
    subsystem: "codes.tim.SF50-TOLD",
    category: "TerrainBackgroundDownloads"
  )

  private let inventory: TerrainRegionInventory?
  private weak var loader: TerrainDataLoader?

  // MARK: - Initializers

  init(inventory: TerrainRegionInventory?, loader: TerrainDataLoader) {
    self.inventory = inventory
    self.loader = loader
  }

  // MARK: - Other Methods

  func downloadDidBegin(_ download: BADownload) {
    guard let region = TerrainRegion.region(forDownloadIdentifier: download.identifier) else {
      return
    }
    logger.info("Download began for \(region.rawValue)")
    report { await $0.backgroundDownloadDidProgress(region: region, fraction: 0) }
  }

  func download(
    _ download: BADownload,
    didWriteBytes _: Int64,
    totalBytesWritten: Int64,
    totalBytesExpectedToWrite totalExpectedBytes: Int64
  ) {
    guard let region = TerrainRegion.region(forDownloadIdentifier: download.identifier),
      totalExpectedBytes > 0
    else { return }

    let fraction = Double(totalBytesWritten) / Double(totalExpectedBytes)
    report { await $0.backgroundDownloadDidProgress(region: region, fraction: fraction) }
  }

  /// Stores a finished payload before returning, because the system reclaims the file afterwards.
  func download(_ download: BADownload, finishedWithFileURL fileURL: URL) {
    guard let region = TerrainRegion.region(forDownloadIdentifier: download.identifier),
      let inventory
    else { return }

    do {
      try inventory.store(fileURL, for: region)
      logger.info("Stored terrain for \(region.rawValue)")
      report { await $0.backgroundDownloadDidFinish(region: region) }
    } catch {
      logger.error("Failed to store \(region.rawValue): \(error.localizedDescription)")
      report { await $0.backgroundDownloadDidFail(region: region, error: error) }
    }
  }

  func download(_ download: BADownload, failedWithError error: any Error) {
    guard let region = TerrainRegion.region(forDownloadIdentifier: download.identifier) else {
      return
    }
    logger.error("Download failed for \(region.rawValue): \(error.localizedDescription)")
    report { await $0.backgroundDownloadDidFail(region: region, error: error) }
  }

  /// Delivers an event to the loader, which lives on the main actor while these callbacks do not.
  private func report(_ event: @escaping @Sendable (TerrainDataLoader) async -> Void) {
    Task { @MainActor [weak loader] in
      guard let loader else { return }
      await event(loader)
    }
  }
}
