import BackgroundAssets
import Combine
import Defaults
import Foundation
import SF50_Shared
import Sentry
import os

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

  /// How often, at most, the app asks the system for newer versions of installed packs.
  ///
  /// The system also checks on its own schedule; this only brings a newly published version
  /// forward for a pilot who opens the app.
  private static let packUpdateCheckInterval: TimeInterval = 24 * 60 * 60

  /// Times a just-downloaded payload is located and checked before it counts as unreadable.
  private static let downloadedPayloadCheckAttempts = 2

  // MARK: - Instance Properties

  /// Current download state.
  @Published private(set) var state: State = .idle

  /// Available regions (downloaded and ready to use).
  @Published private(set) var availableRegions: Set<TerrainRegion> = []

  /// Regions currently being downloaded by the main app.
  @Published private(set) var downloadingRegions: Set<TerrainRegion> = []

  /// Regions with active Background Assets downloads managed by the system.
  @Published private(set) var backgroundDownloadingRegions: Set<TerrainRegion> = []

  /// Fraction complete for each region whose asset pack is downloading, whether the app asked for
  /// it or the system started it.
  @Published private(set) var packDownloadProgress: [TerrainRegion: Double] = [:]

  /// Where each available region's payload was found, as of the last scan or download.
  ///
  /// Locating an asset pack's payload asks the system to stage it, which Apple warns can hang the
  /// UI, so it is done off the main actor and remembered here for the code that runs on it.
  private var payloadURLs: [TerrainRegion: URL] = [:]

  /// Regions whose payload failed to load, or whose digest does not match the one its pack carries.
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

  /// When this process last asked the system for newer versions of installed packs.
  private var lastPackUpdateCheck: Date?

  /// Regions held only in the shared container whose pack has been asked for this session.
  private var legacyRegionsBeingReplaced: Set<TerrainRegion> = []

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
    terrainDirectory.map { .init(directory: $0, manifest: .legacyContainer) }
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
    return payloadURLs[region]
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
    packDownloadProgress[region] = fraction
  }

  /// Takes up a payload the system finished downloading.
  ///
  /// The finished download may be a new version of a region already loaded, so the region is
  /// unloaded first and reloaded from the new payload once that has been verified.
  func backgroundDownloadDidFinish(region: TerrainRegion) {
    backgroundDownloadingRegions.remove(region)
    packDownloadProgress[region] = nil
    corruptedRegions.remove(region)
    Task {
      await TerrainService.shared.unloadRegion(region)
      refreshAvailableRegions()
    }
  }

  /// Asks the system to fetch newer versions of the installed packs, at most once a day.
  func checkForPackUpdatesIfDue() {
    if let lastPackUpdateCheck,
      Date.now.timeIntervalSince(lastPackUpdateCheck) < Self.packUpdateCheckInterval
    {
      return
    }
    lastPackUpdateCheck = .now
    Task { await refreshAssetPackManifest(using: .shared) }
  }

  /// Clears the download's state so the region stops reading as in progress.
  func backgroundDownloadDidFail(region: TerrainRegion, error: any Error) {
    backgroundDownloadingRegions.remove(region)
    packDownloadProgress[region] = nil
    report(error, for: region, operation: "backgroundDownload")
    refreshAvailableRegions()
  }

  /// Refreshes region state by scanning the terrain directory and the asset-pack store.
  ///
  /// Every asset-pack payload is checked against the digest its pack carries before it counts as
  /// available, so a damaged payload never reaches the terrain service. A payload that can't be
  /// read at the moment keeps whatever state its region had: the system swaps a pack's staged file
  /// while installing a new version, and a read that lands in the swap says nothing about the
  /// payload. The scan runs on a background task so the main actor is never blocked while a
  /// payload is hashed.
  func refreshAvailableRegions() {
    let corrupted = corruptedRegions
    Task { [weak self] in
      guard let self else { return }
      let scan = await scanRegions(excluding: corrupted)

      let keptRegions = availableRegions.intersection(scan.unreadable)
      availableRegions = scan.available.union(keptRegions)
      payloadURLs = scan.payloadURLs.merging(
        payloadURLs.filter { keptRegions.contains($0.key) },
        uniquingKeysWith: { scanned, _ in scanned }
      )
      corruptedRegions.formUnion(scan.damaged)
      notePurgedRegions(scan.purged)
      logger.info("Available terrain regions: \(self.availableRegions.map(\.rawValue))")

      scan.legacyOnly.forEach(replaceLegacyPayload)
      loadAvailableRegionsIntoService()
    }
  }

  /// Reads what the shared container and the asset-pack store hold for every region not already
  /// known to be corrupt.
  @concurrent
  private func scanRegions(excluding corrupted: Set<TerrainRegion>) async -> RegionScan {
    let inventory = inventory
    let locator = locator
    let verifier = TerrainPayloadVerifier()

    var scan = RegionScan()
    for region in TerrainRegion.allCases where !corrupted.contains(region) {
      if let inventory {
        clearUnusableLegacyPayloads(for: region, in: inventory)
      }

      switch locator.state(of: region) {
        case .installed(let url, .assetPack):
          switch check(region, payloadAt: url, using: verifier) {
            case .usable:
              scan.available.insert(region)
              scan.payloadURLs[region] = url
              retireLegacyPayload(for: region, in: inventory)
            case .damaged:
              scan.damaged.insert(region)
            case .unreadable:
              scan.unreadable.insert(region)
          }
        case .installed(let url, .legacyContainer):
          logger.info("Terrain for \(region.rawValue) is available from the shared container")
          scan.available.insert(region)
          scan.payloadURLs[region] = url
          scan.legacyOnly.insert(region)
        case .purged:
          logger.notice("Terrain for \(region.rawValue) was requested but is no longer on disk")
          scan.purged.insert(region)
        case .absent:
          break
      }
    }
    return scan
  }

  /// Checks `region`'s installed pack payload against its digest. A payload from a pack that
  /// carries no digest is usable as it stands.
  nonisolated private func check(
    _ region: TerrainRegion,
    payloadAt url: URL,
    using verifier: TerrainPayloadVerifier
  ) -> PayloadCheck {
    do {
      switch try verifier.verdict(for: region, payloadAt: url) {
        case .intact:
          logger.info("Terrain for \(region.rawValue) is available from its verified asset pack")
          return .usable
        case .unverifiable:
          logger.info(
            "Terrain for \(region.rawValue) is available from an asset pack with no digest"
          )
          return .usable
        case .damaged:
          logger.error("Terrain for \(region.rawValue) does not match its pack's digest")
          return .damaged
      }
    } catch {
      logger.notice(
        "Couldn’t read the payload for \(region.rawValue) yet: \(error.localizedDescription)"
      )
      return .unreadable
    }
  }

  /// Deletes shared-container files for `region` that nothing can use: a v2-era compressed
  /// payload, or a payload that doesn't measure what it was published at.
  ///
  /// Nothing writes to the shared container any more, so a short payload is not a download in
  /// progress. It is one that was cut short, and it would otherwise sit there for good.
  nonisolated private func clearUnusableLegacyPayloads(
    for region: TerrainRegion,
    in inventory: TerrainRegionInventory
  ) {
    if inventory.removeLegacyCompressedPayload(for: region) {
      logger.info("Reclaimed a v2-era compressed payload for \(region.rawValue)")
    }
    if case .incomplete(let bytesOnDisk, let expectedBytes) = inventory.state(of: region) {
      logger.notice(
        "Removing a cut-short payload for \(region.rawValue): \(bytesOnDisk) of \(expectedBytes) bytes"
      )
      try? FileManager.default.removeItem(at: inventory.localURL(for: region))
    }
  }

  /// Deletes `region`'s shared-container payload once its pack has taken over.
  nonisolated private func retireLegacyPayload(
    for region: TerrainRegion,
    in inventory: TerrainRegionInventory?
  ) {
    guard let url = inventory?.localURL(for: region),
      FileManager.default.fileExists(atPath: url.path)
    else { return }
    logger.notice(
      "Retiring the shared-container payload for \(region.rawValue); its pack is installed"
    )
    try? FileManager.default.removeItem(at: url)
  }

  /// Asks the system for the pack that replaces `region`'s shared-container payload.
  ///
  /// The shared container holds what was published before the app adopted asset packs, and the
  /// pack holds what is published now. The shared copy stays in use until the pack is installed,
  /// so the pilot is never left without terrain for the region meanwhile.
  private func replaceLegacyPayload(for region: TerrainRegion) {
    guard legacyRegionsBeingReplaced.insert(region).inserted else { return }
    Defaults[.requestedTerrainRegions].insert(region)
    Task {
      do {
        try await ensureAssetPackIsLocal(for: region)
        logger.notice("Replaced the shared-container payload for \(region.rawValue) with its pack")
      } catch {
        logger.error(
          "Couldn’t fetch the pack replacing \(region.rawValue): \(error.localizedDescription)"
        )
        legacyRegionsBeingReplaced.remove(region)
      }
      refreshAvailableRegions()
    }
  }

  /// Deletes terrain data files for a region from disk and clears all tracking state.
  func deleteRegion(_ region: TerrainRegion) async {
    await removePayload(for: region)
    inventory?.removeLegacyCompressedPayload(for: region)
    Defaults[.requestedTerrainRegions].remove(region)

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
    state = .downloading(region: region)

    let transaction = SentrySDK.startTransaction(
      name: "Terrain Download",
      operation: "terrain.download"
    )
    transaction.setTag(value: region.rawValue, key: "terrain.region")

    do {
      try await ensureAssetPackIsLocal(for: region)
      try await verifyDownloadedPayload(for: region)

      // Load the freshly downloaded payload into TerrainService. If it arrived intact but can't
      // be loaded, mark it corrupted so the UI shows "Corrupted" rather than a misleading
      // "Download" button.
      if let fileURL = await payloadState(of: region).url {
        payloadURLs[region] = fileURL
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

  /// Where `region`'s payload is, located off the main actor.
  @concurrent
  private func payloadState(of region: TerrainRegion) async -> TerrainPayloadState {
    locator.state(of: region)
  }

  /// Checks a just-downloaded pack's payload against its digest before anything reads it.
  ///
  /// The system may still be moving the payload into place, so one that can't be read is located
  /// and checked once more before the download counts as failed.
  ///
  /// - Throws: ``TerrainDataLoaderError/payloadDamaged(_:)`` if it doesn't match, after marking
  ///   the region corrupted so the pilot is offered a re-download, or
  ///   ``TerrainDataLoaderError/payloadUnreadable(_:)`` if it can't be read at all.
  private func verifyDownloadedPayload(for region: TerrainRegion) async throws {
    for _ in 1...Self.downloadedPayloadCheckAttempts {
      guard case .installed(let url, .assetPack) = await payloadState(of: region) else { return }
      let result = await Task.detached { [self] in
        check(region, payloadAt: url, using: TerrainPayloadVerifier())
      }.value
      switch result {
        case .usable:
          return
        case .damaged:
          corruptedRegions.insert(region)
          throw TerrainDataLoaderError.payloadDamaged(region)
        case .unreadable:
          continue
      }
    }
    throw TerrainDataLoaderError.payloadUnreadable(region)
  }

  /// Removes whichever copy of `region` the device holds.
  ///
  /// A legacy payload is the app's own file to delete; a pack belongs to the system, which is the
  /// only thing that can reclaim it.
  private func removePayload(for region: TerrainRegion) async {
    payloadURLs[region] = nil
    switch await payloadState(of: region) {
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
  private func ensureAssetPackIsLocal(for region: TerrainRegion) async throws {
    let manager = AssetPackManager.shared
    await refreshAssetPackManifest(using: manager)
    guard let pack = try await manager.manifest.assetPack(withID: region.downloadIdentifier) else {
      throw TerrainDataLoaderError.regionNotAvailable(region)
    }

    try await manager.ensureLocalAvailability(of: pack, requireLatestVersion: true)
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

  /// What checking a pack's payload against its digest found.
  private enum PayloadCheck {
    /// Intact, or from a pack with no digest to check against.
    case usable
    /// The payload doesn't match its pack's digest.
    case damaged
    /// The payload couldn't be read, which says nothing about whether it is intact.
    case unreadable
  }

  /// What one pass over the terrain stores found.
  private struct RegionScan {
    var available: Set<TerrainRegion> = []
    /// Regions whose pack payload doesn't match its digest.
    var damaged: Set<TerrainRegion> = []
    /// Regions whose pack payload couldn't be read this time, and whose state stands.
    var unreadable: Set<TerrainRegion> = []
    /// Where each available region's payload was found.
    var payloadURLs: [TerrainRegion: URL] = [:]
    /// Available regions read from the shared container, awaiting their packs.
    var legacyOnly: Set<TerrainRegion> = []
    var purged: Set<TerrainRegion> = []
  }

  /// Current download state.
  enum State: Equatable {
    case idle
    case downloading(region: TerrainRegion)
    case completed(region: TerrainRegion)
    case failed(region: TerrainRegion, message: String)
  }
}

/// Errors that can occur during terrain data loading.
enum TerrainDataLoaderError: LocalizedError {
  case noStorageAccess
  case downloadFailed(any Error)
  case outOfDiskSpace
  case regionNotAvailable(TerrainRegion)
  case payloadDamaged(TerrainRegion)
  case payloadUnreadable(TerrainRegion)

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
      case .payloadDamaged(let region):
        String(localized: "The downloaded terrain data for \(region.displayName) is damaged.")
      case .payloadUnreadable(let region):
        String(localized: "The downloaded terrain data for \(region.displayName) couldn’t be read.")
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
      case .payloadDamaged:
        String(localized: "Tap “Re-download” to replace it.")
      case .payloadUnreadable:
        String(localized: "Try again in a moment.")
    }
  }
}

extension Error {
  /// Whether this error, or any error in its `NSUnderlyingErrorKey` chain,
  /// represents a "No space left on device" condition.
  ///
  /// A file-system error can arrive wrapped, with the outermost error in a
  /// library's own domain and the `errno` one level down, so recognizing the
  /// condition means walking the chain rather than inspecting only the error in
  /// hand.
  fileprivate var isOutOfDiskSpace: Bool { (self as NSError).isOutOfDiskSpace }
}

extension NSError {
  /// Whether this error or any error beneath it reports exhausted storage.
  ///
  /// `Foundation`'s file APIs report the condition in `NSCocoaErrorDomain`
  /// while the C-level writes `StreamingLZMA` performs report it as POSIX
  /// `ENOSPC`, and either can appear at any depth of the chain.
  fileprivate var isOutOfDiskSpace: Bool {
    if domain == NSPOSIXErrorDomain, code == Int(ENOSPC) { return true }
    if domain == NSCocoaErrorDomain, code == NSFileWriteOutOfSpaceError { return true }
    guard let underlying = userInfo[NSUnderlyingErrorKey] as? NSError else { return false }
    return underlying.isOutOfDiskSpace
  }
}
