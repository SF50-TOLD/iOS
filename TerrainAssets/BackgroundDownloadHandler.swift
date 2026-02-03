import BackgroundAssets
import ExtensionFoundation
import Foundation
import SF50_Shared
import os

/// Background Assets extension for downloading terrain data at install time.
///
/// Downloads the compressed `.srtm.lzma` terrain file for the user's locale region
/// into the shared app group container. The main app detects and decompresses it on launch.
@main
struct DownloaderExtension: BADownloaderExtension {

  private let logger = Logger(
    subsystem: "codes.tim.SF50-TOLD",
    category: "TerrainAssets"
  )

  private let appGroupID = "group.codes.tim.TOLD"
  private let terrainSubdirectory = "Terrain"

  // MARK: - BADownloaderExtension

  func downloads(
    for request: BAContentRequest,
    manifestURL: URL,
    extensionInfo _: BAAppExtensionInfo
  ) -> Set<BADownload> {
    let region = TerrainRegion.localePrefetchRegion
    logger.info(
      "Downloads requested (request: \(request.rawValue)), prefetch region: \(region.rawValue)"
    )

    // Parse the manifest provided by the system (not Bundle.main)
    guard let manifestData = try? Data(contentsOf: manifestURL),
      let manifest = try? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(TerrainManifest.self, from: manifestData)
      }()
    else {
      logger.error("Failed to read or decode manifest at \(manifestURL)")
      return []
    }

    guard let manifestRegion = manifest.region(forID: region.rawValue) else {
      logger.error("Region \(region.rawValue) not found in manifest")
      return []
    }

    // Check if terrain already exists in shared container
    guard
      let containerURL = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: appGroupID
      )
    else {
      logger.error("Cannot access app group container")
      return []
    }

    let terrainDir = containerURL.appendingPathComponent(terrainSubdirectory, isDirectory: true)
    let decompressedURL = terrainDir.appendingPathComponent("\(region.rawValue).srtm")
    let compressedURL = terrainDir.appendingPathComponent(region.filename)

    if FileManager.default.fileExists(atPath: decompressedURL.path)
      || FileManager.default.fileExists(atPath: compressedURL.path)
    {
      logger.info("Terrain for \(region.rawValue) already exists, skipping download")
      return []
    }

    // Build the download URL
    let downloadURLString = manifest.effectiveBaseURL + region.filename
    guard let downloadURL = URL(string: downloadURLString) else {
      logger.error("Invalid download URL: \(downloadURLString)")
      return []
    }

    let download = BAURLDownload(
      identifier: "terrain-\(region.rawValue)",
      request: URLRequest(url: downloadURL),
      essential: true,
      fileSize: manifestRegion.sizeBytes,
      applicationGroupIdentifier: appGroupID,
      priority: .default
    )

    logger.info(
      "Scheduling download: \(region.rawValue) (\(manifestRegion.sizeBytes) bytes) from \(downloadURLString)"
    )
    return [download]
  }

  func backgroundDownload(_ finishedDownload: BADownload, finishedWithFileURL fileURL: URL) {
    logger.info("Download finished: \(finishedDownload.identifier)")

    guard
      let containerURL = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: appGroupID
      )
    else {
      logger.error("Cannot access app group container for finished download")
      return
    }

    let terrainDir = containerURL.appendingPathComponent(terrainSubdirectory, isDirectory: true)

    // Determine the region from the download identifier ("terrain-{rawValue}")
    let regionID = String(finishedDownload.identifier.dropFirst("terrain-".count))
    guard let region = TerrainRegion(rawValue: regionID) else {
      logger.error("Unknown region in download identifier: \(finishedDownload.identifier)")
      return
    }

    let destinationURL = terrainDir.appendingPathComponent(region.filename)

    do {
      // Create Terrain directory if needed
      try FileManager.default.createDirectory(
        at: terrainDir,
        withIntermediateDirectories: true
      )

      // Move from ephemeral location to shared container
      if FileManager.default.fileExists(atPath: destinationURL.path) {
        try FileManager.default.removeItem(at: destinationURL)
      }
      try FileManager.default.moveItem(at: fileURL, to: destinationURL)

      logger.info("Moved terrain file to \(destinationURL.lastPathComponent)")

      // Notify the main app
      let name = "codes.tim.SF50-TOLD.terrainDownloadCompleted" as CFString
      CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        CFNotificationName(name),
        nil,
        nil,
        true
      )
    } catch {
      logger.error("Failed to move downloaded file: \(error.localizedDescription)")
    }
  }

  func backgroundDownload(_ failedDownload: BADownload, failedWithError error: any Error) {
    logger.error(
      "Download failed: \(failedDownload.identifier) — \(error.localizedDescription)"
    )

    // Reschedule as non-essential so it doesn't block app install
    if failedDownload.isEssential {
      let retryDownload = failedDownload.removingEssential()
      do {
        try BADownloadManager.shared.scheduleDownload(retryDownload)
        logger.info("Rescheduled \(failedDownload.identifier) as non-essential")
      } catch {
        logger.error("Failed to reschedule download: \(error.localizedDescription)")
      }
    }
  }
}
