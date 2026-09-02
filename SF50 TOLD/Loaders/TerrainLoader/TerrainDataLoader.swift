import BackgroundAssets
import Foundation
import os
import Sentry
import SF50_Shared
import StreamingLZMA

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

  /// Extension given to a payload still being built, so a scan can't mistake it for a finished one.
  nonisolated private static let scratchFileExtension = "partial"

  /// Configuration shared by the manifest fetch and the region downloads.
  ///
  /// A region runs to several gigabytes, so the resource timeout has to cover a transfer
  /// measured in tens of minutes rather than the minute a request is given to answer.
  nonisolated private static var downloadConfiguration: URLSessionConfiguration {
    let configuration = URLSessionConfiguration.default
    configuration.timeoutIntervalForRequest = 60
    configuration.timeoutIntervalForResource = 1800
    return configuration
  }

  // MARK: - Instance Properties

  /// Current download state.
  @Published private(set) var state: State = .idle

  /// Available regions (downloaded and ready to use).
  @Published private(set) var availableRegions: Set<TerrainRegion> = []

  /// Regions currently being downloaded by the main app.
  @Published private(set) var downloadingRegions: Set<TerrainRegion> = []

  /// Regions with active Background Assets downloads managed by the system.
  @Published private(set) var backgroundDownloadingRegions: Set<TerrainRegion> = []

  /// Regions currently being expanded from a compressed payload.
  @Published private(set) var expandingRegions: Set<TerrainRegion> = []

  /// Regions whose payload is on disk but shorter than the manifest says it should be.
  @Published private(set) var unfinishedRegions: Set<TerrainRegion> = []

  /// Fraction complete for each region the system is currently downloading.
  @Published private(set) var backgroundDownloadProgress: [TerrainRegion: Double] = [:]

  /// Regions whose files exist on disk but failed to load (corrupt or unreadable).
  @Published private(set) var corruptedRegions: Set<TerrainRegion> = []

  /// Logger for debug output.
  nonisolated private let logger = Logger(
    subsystem: "codes.tim.SF50-TOLD",
    category: "TerrainDataLoader"
  )

  /// Emits the intervals that put decompression on an Instruments timeline.
  nonisolated private let signposter = OSSignposter(
    subsystem: "codes.tim.SF50-TOLD",
    category: "TerrainDataLoader"
  )

  /// App group identifier for shared storage.
  nonisolated private let appGroupID = "group.codes.tim.TOLD"

  /// Base URL for terrain data downloads.
  private var baseURL = TerrainManifest.defaultBaseURL.absoluteString

  /// Receives the system's download events; `BADownloadManager` holds its delegate weakly.
  private var backgroundDownloadObserver: TerrainBackgroundDownloadObserver?

  /// URL session for manifest fetches.
  private lazy var urlSession = URLSession(configuration: Self.downloadConfiguration)

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

  // MARK: - Initializers

  init() {
    let observer = TerrainBackgroundDownloadObserver(inventory: inventory, loader: self)
    backgroundDownloadObserver = observer
    BADownloadManager.shared.delegate = observer

    refreshAvailableRegions()
    refreshBackgroundDownloads()
    setupNotificationObserver()
  }

  // MARK: - Type Methods

  /// Expands an LZMA-compressed payload into the form the terrain service reads.
  ///
  /// The output is built under a scratch name and renamed into place only once it is whole, so a
  /// concurrent scan sees either no payload or a complete one — never a half-written file that
  /// would load as corrupt. The compressed original is removed on success.
  nonisolated private static func expandLegacyPayload(
    from sourceURL: URL,
    to destinationURL: URL
  ) throws {
    let scratchURL = destinationURL.appendingPathExtension(Self.scratchFileExtension)
    try? FileManager.default.removeItem(at: scratchURL)

    let inputHandle = try FileHandle(forReadingFrom: sourceURL)
    defer { try? inputHandle.close() }

    FileManager.default.createFile(atPath: scratchURL.path, contents: nil)
    let outputHandle = try FileHandle(forWritingTo: scratchURL)
    defer { try? outputHandle.close() }

    do {
      try inputHandle.lzmaFileDecompress(to: outputHandle, configuration: .highThroughput)
      try outputHandle.synchronize()
      try outputHandle.close()
    } catch {
      try? outputHandle.close()
      try? FileManager.default.removeItem(at: scratchURL)
      if error.isOutOfDiskSpace { throw TerrainDataLoaderError.outOfDiskSpace }
      throw TerrainDataLoaderError.decompressionFailed(error)
    }

    try FileManager.default.moveItem(at: scratchURL, to: destinationURL)
    try? FileManager.default.removeItem(at: sourceURL)
  }

  // MARK: - Public API

  /// Checks if a region's terrain data is available locally.
  func isRegionAvailable(_ region: TerrainRegion) -> Bool {
    availableRegions.contains(region)
  }

  /// Returns the URL to the terrain data file for a region, if available.
  func terrainFileURL(for region: TerrainRegion) -> URL? {
    guard isRegionAvailable(region) else { return nil }
    return payloadURL(for: region)
  }

  /// Queries `BADownloadManager` for active Background Assets downloads.
  func refreshBackgroundDownloads() {
    BADownloadManager.shared.fetchCurrentDownloads { [weak self] downloads, error in
      if let error {
        self?.logger.warning("Failed to fetch BA downloads: \(error.localizedDescription)")
      }

      let regions = Set(
        downloads.compactMap { TerrainRegion.region(forDownloadIdentifier: $0.identifier) }
      )

      Task { @MainActor [weak self] in
        self?.backgroundDownloadingRegions = regions
        self?.logger.info("Active BA downloads: \(regions.map(\.rawValue))")
      }
    }
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
      logger.info("Available terrain regions: \(scan.available.map(\.rawValue))")

      loadAvailableRegionsIntoService()

      for region in scan.pendingExpansion {
        Task { await self.expandPendingPayload(for: region) }
      }
    }
  }

  /// Reads what the shared container holds for every region not already known to be corrupt.
  @concurrent
  private func scanRegions(excluding corrupted: Set<TerrainRegion>) async -> RegionScan {
    guard let inventory else { return .init() }

    var scan = RegionScan()
    for region in TerrainRegion.allCases where !corrupted.contains(region) {
      switch inventory.state(of: region) {
        case .complete:
          scan.available.insert(region)
        case .legacyCompressed:
          logger.info("Found a compressed payload for \(region.rawValue), queuing expansion")
          scan.pendingExpansion.append(region)
        case .incomplete(let bytesOnDisk, let expectedBytes):
          logger.info(
            "Payload for \(region.rawValue) is \(bytesOnDisk) of \(expectedBytes) bytes"
          )
          scan.unfinished.insert(region)
        case .absent:
          break
      }
    }
    return scan
  }

  /// Deletes terrain data files for a region from disk and clears all tracking state.
  func deleteRegion(_ region: TerrainRegion) async {
    if let payloadURL = payloadURL(for: region) {
      try? FileManager.default.removeItem(at: payloadURL)
    }
    if let legacyPayloadURL = legacyPayloadURL(for: region) {
      try? FileManager.default.removeItem(at: legacyPayloadURL)
    }
    unfinishedRegions.remove(region)

    availableRegions.remove(region)
    corruptedRegions.remove(region)

    await TerrainService.shared.unloadRegion(region)

    logger.info("Deleted terrain files for \(region.rawValue)")
  }

  /// Downloads terrain data for a region.
  ///
  /// This method first attempts to use Background Assets for the download.
  /// If Background Assets is not available, it falls back to direct download.
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

    downloadingRegions.insert(region)
    state = .downloading(region: region, progress: nil)

    let transaction = SentrySDK.startTransaction(
      name: "Terrain Download",
      operation: "terrain.download"
    )
    transaction.setTag(value: region.rawValue, key: "terrain.region")

    do {
      // Request download via Background Assets
      try scheduleBackgroundDownload(for: region)

      // If Background Assets isn't available or we want immediate download,
      // fall back to direct download
      try await performDirectDownload(for: region)

      // Load the freshly downloaded file into TerrainService. If the file
      // downloaded OK but can't be loaded, mark it as corrupted so the UI
      // shows "Corrupted" rather than a misleading "Download" button.
      if let fileURL = payloadURL(for: region) {
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
      // Writing the payload and moving it into place both fail with a bare
      // filesystem error when the disk fills, which would otherwise reach the
      // user as an opaque message and Sentry as a bug report.
      let error = error.isOutOfDiskSpace ? TerrainDataLoaderError.outOfDiskSpace : error
      transaction.finish(status: .internalError)
      downloadingRegions.remove(region)
      state = .failed(region: region, message: error.localizedDescription)
      throw error
    }
  }

  // MARK: - Private Methods

  /// Returns the URL this region's payload is stored under in the shared container.
  nonisolated private func payloadURL(for region: TerrainRegion) -> URL? {
    inventory?.localURL(for: region)
  }

  /// Returns the URL of this region's LZMA-compressed payload, which expands to ``payloadURL(for:)``.
  nonisolated private func legacyPayloadURL(for region: TerrainRegion) -> URL? {
    inventory?.legacyCompressedURL(for: region)
  }

  /// Schedules a download via Background Assets.
  private func scheduleBackgroundDownload(for region: TerrainRegion) throws {
    // Store the request for the Background Assets extension
    guard let terrainDir = terrainDirectory else {
      throw TerrainDataLoaderError.noStorageAccess
    }

    // Create terrain directory if needed
    try FileManager.default.createDirectory(
      at: terrainDir,
      withIntermediateDirectories: true
    )

    // Add to requested regions file
    let requestFile = terrainDir.appendingPathComponent("requested-regions.json")

    var requestedRegions: [String] = []
    if let data = try? Data(contentsOf: requestFile),
      let existing = try? JSONDecoder().decode([String].self, from: data)
    {
      requestedRegions = existing
    }

    if !requestedRegions.contains(region.rawValue) {
      requestedRegions.append(region.rawValue)
      let data = try JSONEncoder().encode(requestedRegions)
      try data.write(to: requestFile)
    }

    // Trigger Background Assets check
    if #available(iOS 16.1, *) {
      BADownloadManager.shared.fetchCurrentDownloads { downloads, error in
        if let error {
          self.logger.warning("Failed to fetch downloads: \(error.localizedDescription)")
        }
        self.logger.info("Current downloads: \(downloads.count)")
      }
    }
  }

  /// Fetches the manifest and updates the base URL if provided.
  private func fetchManifestBaseURL() async {
    let bundled = TerrainManifest.bundled

    do {
      let (data, _) = try await urlSession.data(from: TerrainManifest.defaultManifestURL)
      let decoder = JSONDecoder()
      decoder.dateDecodingStrategy = .iso8601
      let remote = try decoder.decode(TerrainManifest.self, from: data)

      // Validate version matches bundled
      guard remote.version == bundled.version else {
        logger.error("Remote manifest version \(remote.version) != bundled \(bundled.version)")
        return
      }

      if !remote.baseURL.isEmpty {
        self.baseURL = remote.baseURL.hasSuffix("/") ? remote.baseURL : remote.baseURL + "/"
        logger.info("Using base URL from manifest: \(self.baseURL)")
      }
    } catch {
      logger.warning("Failed to fetch manifest: \(error.localizedDescription)")
    }
  }

  /// Decompresses a payload off the main actor, bracketed by a signpost interval.
  ///
  /// Expansion runs outside the “Terrain Download” transaction, so the interval is the only
  /// record of what the LZMA pass costs for a given region.
  private func expandPayload(
    from legacyPayloadURL: URL,
    to payloadURL: URL,
    for region: TerrainRegion
  ) async throws {
    let interval = signposter.beginInterval(
      "terrain expand",
      id: signposter.makeSignpostID(),
      "\(region.rawValue, privacy: .public)"
    )
    defer { signposter.endInterval("terrain expand", interval) }

    try await Task.detached(priority: .userInitiated) {
      try Self.expandLegacyPayload(from: legacyPayloadURL, to: payloadURL)
    }.value
  }

  /// Expands a compressed payload found in the shared container into a usable one.
  private func expandPendingPayload(for region: TerrainRegion) async {
    guard let legacyPayloadURL = legacyPayloadURL(for: region),
      let payloadURL = payloadURL(for: region)
    else {
      return
    }

    logger.info("Expanding compressed terrain for \(region.rawValue)…")
    expandingRegions.insert(region)
    state = .expanding(region: region)
    defer { expandingRegions.remove(region) }

    do {
      try await expandPayload(from: legacyPayloadURL, to: payloadURL, for: region)
      availableRegions.insert(region)
      loadAvailableRegionsIntoService()
      logger.info("Terrain for \(region.rawValue) is available")
    } catch {
      report(error, for: region, operation: "expand")
      logger.error(
        "Failed to expand terrain for \(region.rawValue): \(error.localizedDescription)"
      )
      state = .failed(region: region, message: error.localizedDescription)
    }
  }

  /// Downloads a region's payload directly, bypassing Background Assets.
  ///
  /// The payload lands under a scratch name and is renamed into place once whole, so an interrupted
  /// download leaves nothing a scan could mistake for a usable region.
  private func performDirectDownload(for region: TerrainRegion) async throws {
    guard let payloadURL = payloadURL(for: region) else {
      throw TerrainDataLoaderError.noStorageAccess
    }

    await fetchManifestBaseURL()

    let remoteURL = URL(string: baseURL + region.remoteFilename)!
    logger.info("Starting direct download for \(region.rawValue) from \(remoteURL)")

    // A region runs to several gigabytes, so an indeterminate spinner would leave a healthy
    // download and a stalled one looking exactly alike for minutes at a time.
    let (progressUpdates, continuation) = AsyncStream.makeStream(of: Float.self)
    defer { continuation.finish() }

    let reportingProgress = Task { [weak self] in
      for await fraction in progressUpdates {
        self?.state = .downloading(region: region, progress: fraction)
      }
    }
    defer { reportingProgress.cancel() }

    let (tempURL, _) = try await downloadWithRetry(
      from: remoteURL,
      configuration: Self.downloadConfiguration,
      logger: logger,
      label: region.rawValue,
      reportingTo: continuation
    )

    if FileManager.default.fileExists(atPath: payloadURL.path) {
      try FileManager.default.removeItem(at: payloadURL)
    }
    try FileManager.default.moveItem(at: tempURL, to: payloadURL)
    logger.info("Downloaded \(region.rawValue)")
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

  /// Listens for the Darwin notification the Background Assets extension posts on completion.
  private func setupNotificationObserver() {
    CFNotificationCenterAddObserver(
      CFNotificationCenterGetDarwinNotifyCenter(),
      Unmanaged.passUnretained(self).toOpaque(),
      { _, observer, _, _, _ in
        guard let observer else { return }
        let loader = Unmanaged<TerrainDataLoader>.fromOpaque(observer).takeUnretainedValue()
        Task { @MainActor in
          loader.refreshAvailableRegions()
          loader.refreshBackgroundDownloads()
        }
      },
      TerrainDownloadNotification.completed as CFString,
      nil,
      .deliverImmediately
    )
  }

  // MARK: - Nested Types

  /// What one pass over the terrain directory found.
  private struct RegionScan {
    var available: Set<TerrainRegion> = []
    var unfinished: Set<TerrainRegion> = []
    var pendingExpansion: [TerrainRegion] = []
  }

  /// Current download state.
  enum State: Equatable {
    case idle
    case downloading(region: TerrainRegion, progress: Float?)
    case expanding(region: TerrainRegion)
    case completed(region: TerrainRegion)
    case failed(region: TerrainRegion, message: String)

    static func == (lhs: Self, rhs: Self) -> Bool {
      switch (lhs, rhs) {
        case (.idle, .idle):
          return true
        case (.downloading(let r1, let p1), .downloading(let r2, let p2)):
          return r1 == r2 && p1 == p2
        case (.expanding(let r1), .expanding(let r2)):
          return r1 == r2
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
  case downloadFailed(Error)
  case decompressionFailed(Error)
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
      case .decompressionFailed(let error):
        String(localized: "Decompression failed: \(error.localizedDescription)")
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
      case .downloadFailed, .decompressionFailed:
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
  /// `StreamingLZMA` surfaces a failed-write `errno` as `LZMAError.ioFailure`,
  /// whose `CustomNSError` bridging leaves the outermost error in the library's
  /// own domain and carries the `errno` one level down, so recognizing the
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
