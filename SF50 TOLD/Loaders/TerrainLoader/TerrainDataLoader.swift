import BackgroundAssets
import Combine
import Defaults
import Foundation
import os
import Sentry
import SF50_Shared

/// Handles on-demand downloading and management of terrain data.
///
/// ``TerrainDataLoader`` works in conjunction with the Background Assets extension
/// to manage terrain data downloads. It handles:
/// - Checking which regions are available locally
/// - Triggering downloads for missing regions
/// - Decompressing downloaded terrain files
/// - Providing status updates during downloads
///
/// ## Usage
///
/// ```swift
/// let loader = TerrainDataLoader()
///
/// // Check if a region is available
/// if !loader.isRegionAvailable(.europe) {
///     // Request download
///     try await loader.downloadRegion(.europe)
/// }
/// ```
extension Notification.Name {
  static let terrainRegionsDidChange = Notification.Name("terrainRegionsDidChange")
}

@MainActor
final class TerrainDataLoader: ObservableObject {

  // MARK: - Type Properties

  static let shared = TerrainDataLoader()

  // MARK: - Instance Properties

  /// Current download state.
  @Published private(set) var state: State = .idle

  /// Available regions (downloaded and ready to use).
  @Published private(set) var availableRegions: Set<TerrainRegion> = []

  /// Regions currently being downloaded by the main app.
  @Published private(set) var downloadingRegions: Set<TerrainRegion> = []

  /// Regions with active Background Assets downloads managed by the system.
  @Published private(set) var backgroundDownloadingRegions: Set<TerrainRegion> = []

  /// Regions whose payload is on disk but shorter than the manifest says it should be.
  @Published private(set) var unfinishedRegions: Set<TerrainRegion> = []

  /// Fraction complete for each region the system is currently downloading.
  @Published private(set) var backgroundDownloadProgress: [TerrainRegion: Double] = [:]

  /// Regions whose files exist on disk but failed to load (corrupt or unreadable).
  @Published private(set) var corruptedRegions: Set<TerrainRegion> = []

  /// Regions the pilot asked for whose payload is gone.
  ///
  /// Asset packs are purgeable, so the system reclaims one when storage runs short and does not
  /// tell the app. Left unsaid, a region a pilot downloaded for a flight would quietly read as
  /// never downloaded.
  @Published private(set) var purgedRegions: Set<TerrainRegion> = []

  /// Newly purged regions the pilot has not been told about yet.
  @Published private(set) var unannouncedPurgedRegions: Set<TerrainRegion> = []

  /// Logger for debug output.
  nonisolated private let logger = Logger(
    subsystem: "codes.tim.SF50-TOLD",
    category: "TerrainDataLoader"
  )

  /// App group identifier for shared storage.
  nonisolated private let appGroupID = "group.codes.tim.TOLD"

  /// Watches the system's asset-pack downloads for as long as the loader lives.
  private var packStatusTask: Task<Void, Never>?

  /// Returns the URL to the terrain directory in the app group container.
  nonisolated private var terrainDirectory: URL? {
    guard
      let containerURL = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: appGroupID
      )
    else {
      return nil
    }
    return containerURL.appendingPathComponent("Terrain", isDirectory: true)
  }

  /// Reads the shared container and reports what each region's files amount to.
  nonisolated private var inventory: TerrainRegionInventory? {
    terrainDirectory.map { .init(directory: $0, manifest: .bundled) }
  }

  /// Says where each region's payload is, across the shared container and the asset-pack store.
  nonisolated private var locator: TerrainPayloadLocator {
    .init(inventory: inventory, requestedRegions: Defaults[.requestedTerrainRegions])
  }

  // MARK: - Initializers

  init() {
    refreshAvailableRegions()
    observePackDownloads()
  }

  // MARK: - Public API

  /// Checks if a region's terrain data is available locally.
  func isRegionAvailable(_ region: TerrainRegion) -> Bool {
    availableRegions.contains(region)
  }

  /// Returns the URL to the terrain data file for a region, if available.
  func terrainFileURL(for region: TerrainRegion) -> URL? {
    guard isRegionAvailable(region) else { return nil }
    return locator.state(of: region).url
  }

  /// Follows the system's asset-pack downloads for as long as the loader lives.
  ///
  /// Managed packs are fetched by the system, the locale prefetch the downloader extension asks
  /// for included, so this stream is the only way the app learns one is running.
  private func observePackDownloads() {
    packStatusTask?.cancel()
    packStatusTask = Task { [weak self] in
      let updates = await AssetPackManager.shared.statusUpdates
      for await update in updates {
        if Task.isCancelled { break }
        self?.apply(update)
      }
    }
  }

  /// Turns one pack status update into the region state the UI reads.
  private func apply(_ update: AssetPackManager.DownloadStatusUpdate) {
    switch update {
      case .began(let pack), .paused(let pack):
        guard let region = region(of: pack) else { return }
        backgroundDownloadDidProgress(region: region, fraction: 0)
      case .downloading(let pack, let progress):
        guard let region = region(of: pack) else { return }
        backgroundDownloadDidProgress(region: region, fraction: progress.fractionCompleted)
      case .finished(let pack):
        guard let region = region(of: pack) else { return }
        logger.notice("Asset pack for \(region.rawValue) finished downloading")
        backgroundDownloadDidFinish(region: region)
      case .failed(let pack, let error):
        guard let region = region(of: pack) else { return }
        backgroundDownloadDidFail(region: region, error: error)
      @unknown default:
        logger.info("Ignoring an unrecognized asset-pack status update")
    }
  }

  /// The region a pack carries, or `nil` for a pack this app does not recognize.
  private func region(of pack: AssetPack) -> TerrainRegion? {
    TerrainRegion.region(forDownloadIdentifier: pack.id)
  }

  /// Takes up what a scan found missing, and works out what the pilot has yet to be told.
  ///
  /// Only regions that were not already known missing are announced, so repeated scans — every
  /// return to the foreground runs one — do not re-raise the same alert.
  private func notePurgedRegions(_ purged: Set<TerrainRegion>) {
    unannouncedPurgedRegions.formUnion(purged.subtracting(purgedRegions))
    purgedRegions = purged
  }

  /// Marks the purge as told, so it stops raising an alert.
  func acknowledgePurgedRegions() {
    unannouncedPurgedRegions.removeAll()
  }

  /// Records how far along the system's download of `region` is.
  func backgroundDownloadDidProgress(region: TerrainRegion, fraction: Double) {
    backgroundDownloadingRegions.insert(region)
    backgroundDownloadProgress[region] = fraction
  }

  /// Takes up a payload the system finished downloading.
  func backgroundDownloadDidFinish(region: TerrainRegion) {
    backgroundDownloadingRegions.remove(region)
    backgroundDownloadProgress[region] = nil
    corruptedRegions.remove(region)
    refreshAvailableRegions()
  }

  /// Clears the download's state so the region stops reading as in progress.
  func backgroundDownloadDidFail(region: TerrainRegion, error: any Error) {
    backgroundDownloadingRegions.remove(region)
    backgroundDownloadProgress[region] = nil
    report(error, for: region, operation: "backgroundDownload")
    refreshAvailableRegions()
  }

  /// Refreshes region state by scanning the terrain directory.
  ///
  /// A region whose payload is short is recorded as unfinished rather than available, so a download
  /// still in flight never reaches the terrain service and never reads as corrupt. The filesystem
  /// scan runs on a background task so the main actor is never blocked.
  func refreshAvailableRegions() {
    let corrupted = corruptedRegions
    Task { [weak self] in
      guard let self else { return }
      let scan = await scanRegions(excluding: corrupted)

      availableRegions = scan.available
      unfinishedRegions = scan.unfinished
      notePurgedRegions(scan.purged)
      logger.info("Available terrain regions: \(scan.available.map(\.rawValue))")

      loadAvailableRegionsIntoService()
    }
  }

  /// Reads what the shared container holds for every region not already known to be corrupt.
  @concurrent
  private func scanRegions(excluding corrupted: Set<TerrainRegion>) async -> RegionScan {
    let inventory = inventory
    let locator = locator

    var scan = RegionScan()
    for region in TerrainRegion.allCases where !corrupted.contains(region) {
      if inventory?.removeLegacyCompressedPayload(for: region) == true {
        logger.info("Reclaimed a v2-era compressed payload for \(region.rawValue)")
      }

      if case .incomplete(let bytesOnDisk, let expectedBytes) = inventory?.state(of: region) {
        logger.info("Payload for \(region.rawValue) is \(bytesOnDisk) of \(expectedBytes) bytes")
        scan.unfinished.insert(region)
        continue
      }

      switch locator.state(of: region) {
        case .installed(_, let source):
          logger.info(
            "Terrain for \(region.rawValue) is available from \(String(describing: source))"
          )
          scan.available.insert(region)
        case .purged:
          logger.notice("Terrain for \(region.rawValue) was requested but is no longer on disk")
          scan.purged.insert(region)
        case .absent:
          break
      }
    }
    return scan
  }

  /// Deletes terrain data files for a region from disk and clears all tracking state.
  func deleteRegion(_ region: TerrainRegion) async {
    await removePayload(for: region)
    inventory?.removeLegacyCompressedPayload(for: region)
    Defaults[.requestedTerrainRegions].remove(region)
    unfinishedRegions.remove(region)

    availableRegions.remove(region)
    corruptedRegions.remove(region)

    await TerrainService.shared.unloadRegion(region)

    logger.info("Deleted terrain files for \(region.rawValue)")
  }

  /// Downloads terrain data for a region.
  ///
  /// The system owns the transfer, so it survives the app being backgrounded or suspended and
  /// draws its own progress and cancel affordances. Tapping Download and walking away now leaves
  /// a running download rather than a stalled one.
  ///
  /// - Parameter region: The region to download
  func downloadRegion(_ region: TerrainRegion) async throws {
    if corruptedRegions.contains(region) {
      await deleteRegion(region)
    }

    guard !isRegionAvailable(region) else {
      logger.info("Region \(region.rawValue) already available")
      return
    }

    guard !downloadingRegions.contains(region),
      !backgroundDownloadingRegions.contains(region)
    else {
      logger.info("Region \(region.rawValue) already downloading")
      return
    }

    Defaults[.requestedTerrainRegions].insert(region)
    downloadingRegions.insert(region)
    state = .downloading(region: region, progress: nil)

    let transaction = SentrySDK.startTransaction(
      name: "Terrain Download",
      operation: "terrain.download"
    )
    transaction.setTag(value: region.rawValue, key: "terrain.region")

    do {
      try await ensureAssetPackIsLocal(for: region)

      // Load the freshly downloaded payload into TerrainService. If it arrived intact but can't
      // be loaded, mark it corrupted so the UI shows "Corrupted" rather than a misleading
      // "Download" button.
      if let fileURL = locator.state(of: region).url {
        let loadSpan = transaction.startChild(
          operation: "terrain.load",
          description: "Load \(region.rawValue) into TerrainService"
        )
        do {
          try await TerrainService.shared.loadRegion(region, from: fileURL)
          loadSpan.finish()
        } catch {
          loadSpan.finish(status: .internalError)
          logger.error(
            "Downloaded \(region.rawValue) but failed to load into TerrainService: \(error.localizedDescription)"
          )
          corruptedRegions.insert(region)
          throw error
        }
      }

      availableRegions.insert(region)
      downloadingRegions.remove(region)
      state = .completed(region: region)

      transaction.finish()
      NotificationCenter.default.post(name: .terrainRegionsDidChange, object: nil)
      logger.info("Region \(region.rawValue) downloaded and loaded")
    } catch {
      // A pack that will not fit fails with a bare filesystem error, which would otherwise
      // reach the user as an opaque message and Sentry as a bug report.
      let error = error.isOutOfDiskSpace ? TerrainDataLoaderError.outOfDiskSpace : error
      transaction.finish(status: .internalError)
      downloadingRegions.remove(region)
      state = .failed(region: region, message: error.localizedDescription)
      throw error
    }
  }

  // MARK: - Private Methods

  /// Removes whichever copy of `region` the device holds.
  ///
  /// A legacy payload is the app's own file to delete; a pack belongs to the system, which is the
  /// only thing that can reclaim it.
  private func removePayload(for region: TerrainRegion) async {
    switch locator.state(of: region) {
      case .installed(let url, .legacyContainer):
        try? FileManager.default.removeItem(at: url)
      case .installed(_, .assetPack):
        do {
          try await AssetPackManager.shared.remove(assetPackWithID: region.downloadIdentifier)
        } catch {
          logger.error(
            "Failed to remove the asset pack for \(region.rawValue): \(error.localizedDescription)"
          )
        }
      case .purged, .absent:
        break
    }
  }

  /// Brings the manager's copy of the published manifest up to date, best effort.
  ///
  /// The system reads the manifest on install and update events, so a pack published since the
  /// last one — or a launch that never saw such an event — is a pack the manager cannot resolve.
  /// A failure here is not fatal: whatever manifest it already holds may still name the pack.
  private func refreshAssetPackManifest(using manager: AssetPackManager) async {
    do {
      let (updating, removed) = try await manager.checkForUpdates()
      logger.info(
        "Asset-pack manifest refreshed; \(updating.count) updating, \(removed.count) removed"
      )
    } catch {
      logger.warning(
        "Couldn’t refresh the asset-pack manifest: \(error.localizedDescription)"
      )
    }
  }

  /// Asks the system for `region`'s asset pack and waits until it is on disk.
  ///
  /// The system owns the transfer, so this survives the app being backgrounded and resumes on its
  /// own. Progress does not come back through here — it arrives on the status stream, which
  /// reports system-driven downloads whether or not anyone is awaiting one.
  ///
  /// `requireLatestVersion:` only exists from iOS 26.4; below that the single-argument form is the
  /// whole API, and a device accepts whichever version it already holds.
  private func ensureAssetPackIsLocal(for region: TerrainRegion) async throws {
    let manager = AssetPackManager.shared
    await refreshAssetPackManifest(using: manager)
    let pack = try await manager.assetPack(withID: region.downloadIdentifier)

    if #available(iOS 26.4, *) {
      try await manager.ensureLocalAvailability(of: pack, requireLatestVersion: true)
    } else {
      try await manager.ensureLocalAvailability(of: pack)
    }
  }

  /// Reports a terrain failure to Sentry unless it is one the user caused and can fix.
  private func report(_ error: any Error, for region: TerrainRegion, operation: String) {
    guard (error as? TerrainDataLoaderError)?.isReportable ?? true else { return }
    SentrySDK.capture(error: error) { scope in
      scope.setTag(value: region.rawValue, key: "terrain.region")
      scope.setTag(value: operation, key: "terrain.operation")
      scope.setFingerprint(["terrain", operation])
    }
  }

  /// Loads any available-but-not-yet-loaded regions into ``TerrainService/shared``
  /// and posts ``Notification.Name/terrainRegionsDidChange`` when new data is loaded.
  private func loadAvailableRegionsIntoService() {
    Task {
      var didChange = false
      for region in availableRegions {
        guard let url = terrainFileURL(for: region) else { continue }
        let alreadyLoaded = await TerrainService.shared.isRegionLoaded(region)
        if !alreadyLoaded {
          do {
            try await TerrainService.shared.loadRegion(region, from: url)
            didChange = true
            logger.info("Loaded \(region.rawValue) into TerrainService")
          } catch {
            SentrySDK.capture(error: error) { scope in
              scope.setTag(value: region.rawValue, key: "terrain.region")
              scope.setTag(value: "load", key: "terrain.operation")
              scope.setFingerprint(["terrain", "load"])
            }
            logger.error(
              "Failed to load \(region.rawValue) into TerrainService: \(error.localizedDescription)"
            )
            availableRegions.remove(region)
            corruptedRegions.insert(region)
            didChange = true
          }
        }
      }
      if didChange {
        NotificationCenter.default.post(name: .terrainRegionsDidChange, object: nil)
      }
    }
  }

  // MARK: - Nested Types

  /// What one pass over the terrain directory found.
  private struct RegionScan {
    var available: Set<TerrainRegion> = []
    var unfinished: Set<TerrainRegion> = []
    var purged: Set<TerrainRegion> = []
  }

  /// Current download state.
  enum State: Equatable {
    case idle
    case downloading(region: TerrainRegion, progress: Float?)
    case completed(region: TerrainRegion)
    case failed(region: TerrainRegion, message: String)

    static func == (lhs: Self, rhs: Self) -> Bool {
      switch (lhs, rhs) {
        case (.idle, .idle):
          return true
        case (.downloading(let r1, let p1), .downloading(let r2, let p2)):
          return r1 == r2 && p1 == p2
        case (.completed(let r1), .completed(let r2)):
          return r1 == r2
        case (.failed(let r1, let m1), .failed(let r2, let m2)):
          return r1 == r2 && m1 == m2
        default:
          return false
      }
    }
  }
}

/// Errors that can occur during terrain data loading.
enum TerrainDataLoaderError: LocalizedError {
  case noStorageAccess
  case downloadFailed(any Error)
  case outOfDiskSpace
  case regionNotAvailable(TerrainRegion)

  /// Whether this error should be reported to Sentry.
  ///
  /// User-side conditions like running out of disk space are not actionable
  /// for the developer and are filtered out at the capture sites.
  var isReportable: Bool {
    switch self {
      case .outOfDiskSpace: false
      default: true
    }
  }

  var errorDescription: String? {
    String(localized: "Terrain data couldn’t be loaded.")
  }

  var failureReason: String? {
    switch self {
      case .noStorageAccess:
        String(localized: "Cannot access the terrain storage location.")
      case .downloadFailed(let error):
        String(localized: "Download failed: \(error.localizedDescription)")
      case .outOfDiskSpace:
        String(localized: "Your device is out of storage space.")
      case .regionNotAvailable(let region):
        String(localized: "Terrain data for \(region.displayName) is not available for download.")
    }
  }

  var recoverySuggestion: String? {
    switch self {
      case .noStorageAccess:
        String(localized: "Check that the app has permission to access storage.")
      case .downloadFailed:
        String(localized: "Check your internet connection and try again.")
      case .outOfDiskSpace:
        String(
          localized:
            "Free up space on your device and try again. The download will resume from where it left off."
        )
      case .regionNotAvailable:
        nil
    }
  }
}

private extension Error {
  /// Whether this error, or any error in its `NSUnderlyingErrorKey` chain,
  /// represents a "No space left on device" condition.
  ///
  /// A file-system error can arrive wrapped, with the outermost error in a
  /// library's own domain and the `errno` one level down, so recognizing the
  /// condition means walking the chain rather than inspecting only the error in
  /// hand.
  var isOutOfDiskSpace: Bool { (self as NSError).isOutOfDiskSpace }
}

private extension NSError {
  /// Whether this error or any error beneath it reports exhausted storage.
  ///
  /// `Foundation`'s file APIs report the condition in `NSCocoaErrorDomain`
  /// while the C-level writes `StreamingLZMA` performs report it as POSIX
  /// `ENOSPC`, and either can appear at any depth of the chain.
  var isOutOfDiskSpace: Bool {
    if domain == NSPOSIXErrorDomain, code == Int(ENOSPC) { return true }
    if domain == NSCocoaErrorDomain, code == NSFileWriteOutOfSpaceError { return true }
    guard let underlying = userInfo[NSUnderlyingErrorKey] as? NSError else { return false }
    return underlying.isOutOfDiskSpace
  }
}
