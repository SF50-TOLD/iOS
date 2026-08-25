import BackgroundAssets
import ExtensionFoundation
import Foundation
import SF50_Shared
import os

/// Background Assets extension that fetches terrain for the device's region after installation.
///
/// The download is non-essential, so it never blocks installation or first launch: the app is fully
/// usable without terrain, and the main app shows the download's progress in its terrain settings.
/// The payload is stored under the shared container's terrain directory, where the app finds it.
@main
struct DownloaderExtension: BADownloaderExtension {

  // MARK: - Type Properties

  private static let appGroupID = "group.codes.tim.TOLD",
    terrainSubdirectory = "Terrain"

  // MARK: - Instance Properties

  private let logger = Logger(
    subsystem: "codes.tim.SF50-TOLD",
    category: "TerrainAssets"
  )

  private var terrainDirectory: URL? {
    FileManager.default
      .containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupID)?
      .appendingPathComponent(Self.terrainSubdirectory, isDirectory: true)
  }

  // MARK: - Other Methods

  func downloads(
    for request: BAContentRequest,
    manifestURL: URL,
    extensionInfo _: BAAppExtensionInfo
  ) -> Set<BADownload> {
    let region = TerrainRegion.localePrefetchRegion
    logger.notice(
      "Downloads requested (request: \(request.rawValue, privacy: .public)), prefetch region: \(region.rawValue, privacy: .public)"
    )

    guard let manifest = manifest(at: manifestURL) else { return [] }

    guard let manifestRegion = manifest.region(forID: region.rawValue) else {
      logger.error("Region \(region.rawValue, privacy: .public) is absent from the manifest")
      return []
    }

    guard let terrainDirectory else {
      logger.error("No app group container for \(Self.appGroupID, privacy: .public)")
      return []
    }

    let inventory = TerrainRegionInventory(directory: terrainDirectory, manifest: manifest)
    let state = inventory.state(of: region)
    guard state.needsDownload else {
      logger.notice(
        """
        Terrain for \(region.rawValue, privacy: .public) is \
        \(String(describing: state), privacy: .public), not downloading
        """
      )
      return []
    }

    guard let downloadURL = URL(string: manifest.effectiveBaseURL + region.remoteFilename) else {
      logger.error("Invalid download URL for \(region.rawValue, privacy: .public)")
      return []
    }

    logger.notice(
      "Scheduling download: \(region.rawValue, privacy: .public) (\(manifestRegion.sizeBytes, privacy: .public) bytes) from \(downloadURL, privacy: .public)"
    )
    return [
      BAURLDownload(
        identifier: region.downloadIdentifier,
        request: URLRequest(url: downloadURL),
        essential: false,
        fileSize: manifestRegion.sizeBytes,
        applicationGroupIdentifier: Self.appGroupID,
        priority: .default
      )
    ]
  }

  func backgroundDownload(_ finishedDownload: BADownload, finishedWithFileURL fileURL: URL) {
    logger.notice("Download finished: \(finishedDownload.identifier, privacy: .public)")

    guard let region = region(of: finishedDownload),
      let terrainDirectory
    else { return }

    do {
      try TerrainRegionInventory.store(fileURL, for: region, in: terrainDirectory)
      logger.notice("Stored terrain for \(region.rawValue, privacy: .public)")
      notifyAppOfCompletedDownload()
    } catch {
      logger.error(
        "Failed to store downloaded file: \(error.localizedDescription, privacy: .public)"
      )
    }
  }

  func backgroundDownload(_ failedDownload: BADownload, failedWithError error: any Error) {
    logger.error(
      "Download failed: \(failedDownload.identifier, privacy: .public) — \(error.localizedDescription, privacy: .public)"
    )
  }

  /// Reads the manifest the system fetched from `BAManifestURL`.
  private func manifest(at manifestURL: URL) -> TerrainManifest? {
    do {
      let decoder = JSONDecoder()
      decoder.dateDecodingStrategy = .iso8601
      return try decoder.decode(TerrainManifest.self, from: Data(contentsOf: manifestURL))
    } catch {
      logger.error(
        "Failed to read manifest at \(manifestURL, privacy: .public): \(error.localizedDescription, privacy: .public)"
      )
      return nil
    }
  }

  private func region(of download: BADownload) -> TerrainRegion? {
    guard let region = TerrainRegion.region(forDownloadIdentifier: download.identifier) else {
      logger.error(
        "Unknown region in download identifier: \(download.identifier, privacy: .public)"
      )
      return nil
    }
    return region
  }

  private func notifyAppOfCompletedDownload() {
    CFNotificationCenterPostNotification(
      CFNotificationCenterGetDarwinNotifyCenter(),
      CFNotificationName(TerrainDownloadNotification.completed as CFString),
      nil,
      nil,
      true
    )
  }
}
