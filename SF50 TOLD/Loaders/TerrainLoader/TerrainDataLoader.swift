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

  /// Manifest URL for terrain data.
  private static let manifestURL = URL(
    string: TerrainManifest.defaultBaseURL.absoluteString + "terrain-manifest.json"
  )!

  // MARK: - Instance Properties

  /// Current download state.
  @Published private(set) var state: State = .idle

  /// Available regions (downloaded and ready to use).
  @Published private(set) var availableRegions: Set<TerrainRegion> = []

  /// Regions currently being downloaded by the main app.
  @Published private(set) var downloadingRegions: Set<TerrainRegion> = []

  /// Regions with active Background Assets downloads managed by the system.
  @Published private(set) var backgroundDownloadingRegions: Set<TerrainRegion> = []

  /// Regions currently being decompressed.
  @Published private(set) var decompressingRegions: Set<TerrainRegion> = []

  /// Regions whose files exist on disk but failed to load (corrupt or unreadable).
  @Published private(set) var corruptedRegions: Set<TerrainRegion> = []

  /// Logger for debug output.
  nonisolated private let logger = Logger(
    subsystem: "codes.tim.SF50-TOLD",
    category: "TerrainDataLoader"
  )

  /// App group identifier for shared storage.
  nonisolated private let appGroupID = "group.codes.tim.TOLD"

  /// Base URL for terrain data downloads.
  private var baseURL = TerrainManifest.defaultBaseURL.absoluteString

  /// URL session for downloads.
  private lazy var urlSession: URLSession = {
    let config = URLSessionConfiguration.default
    config.timeoutIntervalForRequest = 60
    config.timeoutIntervalForResource = 1800  // 30 minutes for large files
    return URLSession(configuration: config)
  }()

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

  // MARK: - Initializers

  init() {
    // Scan for available regions and check for active BA downloads
    refreshAvailableRegions()
    refreshBackgroundDownloads()

    // Listen for download completion notifications from Background Assets extension
    setupNotificationObserver()
  }

  // MARK: - Type Methods

  /// Streaming LZMA decompression using StreamingLZMA.
  ///
  /// Reads the compressed `.lzma` file and writes the decompressed output incrementally,
  /// keeping memory usage bounded regardless of file size. Removes the compressed
  /// file after successful decompression.
  nonisolated private static func streamingDecompress(
    from sourceURL: URL,
    to destinationURL: URL
  ) throws {
    let inputHandle = try FileHandle(forReadingFrom: sourceURL)
    defer { try? inputHandle.close() }

    FileManager.default.createFile(atPath: destinationURL.path, contents: nil)
    let outputHandle = try FileHandle(forWritingTo: destinationURL)
    defer { try? outputHandle.close() }

    do {
      try inputHandle.lzmaFileDecompress(
        to: outputHandle,
        configuration: .highThroughput
      )
      // Flush to disk before closing so the file is ready for pread
      try outputHandle.synchronize()
    } catch {
      try? outputHandle.close()
      try? FileManager.default.removeItem(at: destinationURL)
      if error.isOutOfDiskSpace {
        throw TerrainDataLoaderError.outOfDiskSpace
      }
      throw TerrainDataLoaderError.decompressionFailed(error)
    }

    // Remove compressed file after successful decompression
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
    return decompressedFileURL(for: region)
  }

  /// Queries `BADownloadManager` for active Background Assets downloads.
  func refreshBackgroundDownloads() {
    BADownloadManager.shared.fetchCurrentDownloads { [weak self] downloads, error in
      if let error {
        self?.logger.warning("Failed to fetch BA downloads: \(error.localizedDescription)")
      }

      let regions = Set(
        downloads.compactMap { download -> TerrainRegion? in
          guard download.identifier.hasPrefix("terrain-") else { return nil }
          let regionID = String(download.identifier.dropFirst("terrain-".count))
          return TerrainRegion(rawValue: regionID)
        }
      )

      Task { @MainActor [weak self] in
        self?.backgroundDownloadingRegions = regions
        self?.logger.info("Active BA downloads: \(regions.map(\.rawValue))")
      }
    }
  }

  /// Refreshes the list of available regions by scanning the terrain directory.
  ///
  /// Also detects compressed `.srtm.lzma` files left by the Background Assets
  /// extension and triggers async decompression for them. The filesystem scan
  /// runs on a background task so the main actor is never blocked.
  func refreshAvailableRegions() {
    let corrupted = corruptedRegions
    Task.detached(priority: .userInitiated) { [self] in
      var available = Set<TerrainRegion>()
      var pendingDecompression = [TerrainRegion]()

      for region in TerrainRegion.allCases where !corrupted.contains(region) {
        if let url = decompressedFileURL(for: region),
          FileManager.default.fileExists(atPath: url.path)
        {
          available.insert(region)
        } else if let compressed = compressedFileURL(for: region),
          FileManager.default.fileExists(atPath: compressed.path)
        {
          logger.info(
            "Found BA-downloaded compressed file for \(region.rawValue), queuing decompression"
          )
          pendingDecompression.append(region)
        }
      }

      await MainActor.run {
        self.availableRegions = available
        self.logger.info("Available terrain regions: \(available.map(\.rawValue))")

        self.loadAvailableRegionsIntoService()

        // Decompress any files left by the Background Assets extension
        for region in pendingDecompression {
          Task {
            await self.decompressPendingDownload(for: region)
          }
        }
      }
    }
  }

  /// Deletes terrain data files for a region from disk and clears all tracking state.
  func deleteRegion(_ region: TerrainRegion) async {
    if let decompressedURL = decompressedFileURL(for: region) {
      try? FileManager.default.removeItem(at: decompressedURL)
    }
    if let compressedURL = compressedFileURL(for: region) {
      try? FileManager.default.removeItem(at: compressedURL)
    }

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
      if let fileURL = decompressedFileURL(for: region) {
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
      transaction.finish(status: .internalError)
      downloadingRegions.remove(region)
      state = .failed(region: region, message: error.localizedDescription)
      throw error
    }
  }

  /// Determines which region contains an airport and whether it's available.
  ///
  /// When multiple regions cover the coordinate, prioritizes:
  /// 1. Already available regions
  /// 2. Currently downloading regions
  /// 3. Regions that need download
  func regionStatus(for coordinate: (latitude: Double, longitude: Double)) -> RegionStatus {
    let regions = TerrainRegion.containing(
      latitude: coordinate.latitude,
      longitude: coordinate.longitude
    )

    guard let firstRegion = regions.first else {
      return .notCovered
    }

    // Prefer already available regions
    if let available = regions.first(where: { isRegionAvailable($0) }) {
      return .available(available)
    }

    // Then prefer downloading regions (direct or Background Assets)
    if let downloading = regions.first(where: {
      downloadingRegions.contains($0) || backgroundDownloadingRegions.contains($0)
    }) {
      return .downloading(downloading)
    }

    return .needsDownload(firstRegion)
  }

  // MARK: - Private Methods

  /// Returns the URL to the decompressed terrain file for a region.
  nonisolated private func decompressedFileURL(for region: TerrainRegion) -> URL? {
    terrainDirectory?.appendingPathComponent("\(region.rawValue).srtm")
  }

  /// Returns the URL to the compressed terrain file for a region.
  nonisolated private func compressedFileURL(for region: TerrainRegion) -> URL? {
    terrainDirectory?.appendingPathComponent(region.filename)
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
      let (data, _) = try await urlSession.data(from: Self.manifestURL)
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

  /// Decompresses a compressed terrain file left by the Background Assets extension.
  ///
  /// Called when `refreshAvailableRegions()` finds a `.srtm.lzma` file without
  /// a corresponding decompressed `.srtm` file.
  private func decompressPendingDownload(for region: TerrainRegion) async {
    guard let compressedURL = compressedFileURL(for: region),
      let decompressedURL = decompressedFileURL(for: region)
    else {
      return
    }

    logger.info("Decompressing BA-downloaded terrain for \(region.rawValue)…")
    decompressingRegions.insert(region)

    do {
      try await Task.detached(priority: .userInitiated) {
        try Self.streamingDecompress(from: compressedURL, to: decompressedURL)
      }.value
      decompressingRegions.remove(region)
      availableRegions.insert(region)
      loadAvailableRegionsIntoService()
      logger.info("BA terrain for \(region.rawValue) is now available")
    } catch {
      if (error as? TerrainDataLoaderError)?.isReportable ?? true {
        SentrySDK.capture(error: error) { scope in
          scope.setTag(value: region.rawValue, key: "terrain.region")
          scope.setTag(value: "decompress", key: "terrain.operation")
          scope.setFingerprint(["terrain", "decompress"])
        }
      }
      decompressingRegions.remove(region)
      logger.error(
        "Failed to decompress BA terrain for \(region.rawValue): \(error.localizedDescription)"
      )
      state = .failed(region: region, message: error.localizedDescription)
    }
  }

  /// Performs a direct download of terrain data.
  private func performDirectDownload(for region: TerrainRegion) async throws {
    guard let compressedURL = compressedFileURL(for: region),
      let decompressedURL = decompressedFileURL(for: region)
    else {
      throw TerrainDataLoaderError.noStorageAccess
    }

    // Update base URL from manifest
    await fetchManifestBaseURL()

    let remoteURL = URL(string: baseURL + region.compressedFilename)!

    logger.info("Starting direct download for \(region.rawValue) from \(remoteURL)")

    // Download with retry and resume data support
    let (tempURL, _) = try await urlSession.downloadWithRetry(
      from: remoteURL,
      logger: logger,
      label: region.rawValue
    )

    // Move to final location
    if FileManager.default.fileExists(atPath: compressedURL.path) {
      try FileManager.default.removeItem(at: compressedURL)
    }
    try FileManager.default.moveItem(at: tempURL, to: compressedURL)

    logger.info("Downloaded \(region.rawValue), decompressing…")
    state = .decompressing(region: region)

    let decompressSpan = SentrySDK.span?.startChild(
      operation: "terrain.decompress",
      description: "Decompress \(region.rawValue)"
    )
    do {
      try await Task.detached(priority: .userInitiated) {
        try Self.streamingDecompress(from: compressedURL, to: decompressedURL)
      }.value
      decompressSpan?.finish()
    } catch {
      decompressSpan?.finish(status: .internalError)
      throw error
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

  /// Sets up notification observer for download completion.
  private func setupNotificationObserver() {
    // Listen for Darwin notification from Background Assets extension
    let notificationName = "codes.tim.SF50-TOLD.terrainDownloadCompleted"

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
      notificationName as CFString,
      nil,
      .deliverImmediately
    )
  }

  // MARK: - Nested Types

  /// Current download state.
  enum State: Equatable {
    case idle
    case downloading(region: TerrainRegion, progress: Float?)
    case decompressing(region: TerrainRegion)
    case completed(region: TerrainRegion)
    case failed(region: TerrainRegion, message: String)

    static func == (lhs: Self, rhs: Self) -> Bool {
      switch (lhs, rhs) {
        case (.idle, .idle):
          return true
        case (.downloading(let r1, let p1), .downloading(let r2, let p2)):
          return r1 == r2 && p1 == p2
        case (.decompressing(let r1), .decompressing(let r2)):
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

  /// Status of terrain coverage for a location.
  enum RegionStatus: Equatable {
    case available(TerrainRegion)
    case needsDownload(TerrainRegion)
    case downloading(TerrainRegion)
    case notCovered
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
  /// Whether this error (or any error in its `NSUnderlyingErrorKey` chain)
  /// represents a POSIX `ENOSPC` "No space left on device" condition.
  ///
  /// `StreamingLZMA` surfaces a failed-write `errno` as `LZMAError.ioFailure`,
  /// which bridges (via `CustomNSError`) to an `NSError` carrying an
  /// `NSPOSIXErrorDomain` underlying error, so the typed checks below are
  /// sufficient.
  var isOutOfDiskSpace: Bool {
    let nsError = self as NSError
    if nsError.domain == NSPOSIXErrorDomain, nsError.code == Int(ENOSPC) {
      return true
    }
    if let posix = self as? POSIXError, posix.code == .ENOSPC {
      return true
    }
    if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Self {
      return underlying.isOutOfDiskSpace
    }
    return false
  }
}
