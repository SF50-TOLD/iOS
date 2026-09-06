import Combine
import Foundation
import Sentry
import SF50_Shared
import SwiftUI

/// View model for terrain data management in the iOS app.
///
/// ``TerrainDataLoaderViewModel`` provides UI state for:
/// - Displaying available terrain regions
/// - Managing download requests
/// - Showing download progress
/// - Handling errors
///
/// ## Usage
///
/// ```swift
/// @StateObject private var terrainVM = TerrainDataLoaderViewModel()
///
/// // In view body:
/// ForEach(terrainVM.allRegions) { region in
///     TerrainRegionRow(
///         region: region,
///         isAvailable: terrainVM.isAvailable(region),
///         isDownloading: terrainVM.isDownloading(region)
///     ) {
///         terrainVM.downloadRegion(region)
///     }
/// }
/// ```
@MainActor
final class TerrainDataLoaderViewModel: ObservableObject, WithIdentifiableError {

  // MARK: - Instance Properties

  /// All available terrain regions.
  let allRegions: [TerrainRegion] = TerrainRegion.allCases.sorted {
    $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
  }

  /// Current download state.
  @Published private(set) var downloadState: DownloadState = .idle

  /// Current error, if any.
  var error: (any Error)?

  /// The underlying terrain data loader.
  private let loader = TerrainDataLoader.shared

  /// Cancellables for Combine subscriptions.
  private var cancellables = Set<AnyCancellable>()

  /// Total size of downloaded terrain data on disk in bytes.
  var totalDownloadedSize: Int64 {
    allRegions
      .filter { isAvailable($0) }
      .compactMap { loader.terrainFileURL(for: $0) }
      .reduce(into: Int64(0)) { total, url in
        let size =
          (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64)
          ?? 0
        total += size
      }
  }

  // MARK: - Initializers

  init() {
    // Subscribe to loader state changes
    loader.$state
      .sink { [weak self] state in
        self?.handleStateChange(state)
      }
      .store(in: &cancellables)

    loader.$availableRegions
      .sink { [weak self] _ in
        self?.objectWillChange.send()
      }
      .store(in: &cancellables)

    loader.$downloadingRegions
      .sink { [weak self] _ in
        self?.objectWillChange.send()
      }
      .store(in: &cancellables)

    loader.$backgroundDownloadingRegions
      .sink { [weak self] _ in
        self?.objectWillChange.send()
      }
      .store(in: &cancellables)

    loader.$purgedRegions
      .sink { [weak self] _ in
        self?.objectWillChange.send()
      }
      .store(in: &cancellables)

    loader.$corruptedRegions
      .sink { [weak self] _ in
        self?.objectWillChange.send()
      }
      .store(in: &cancellables)

    loader.$unfinishedRegions
      .sink { [weak self] _ in
        self?.objectWillChange.send()
      }
      .store(in: &cancellables)

    loader.$backgroundDownloadProgress
      .sink { [weak self] _ in
        self?.objectWillChange.send()
      }
      .store(in: &cancellables)

    // A region reaches this set only after a full-length payload fails to load, so every arrival
    // here is a payload the user has to re-download.
    loader.$corruptedRegions
      .removeDuplicates()
      .dropFirst()
      .filter { !$0.isEmpty }
      .sink { [weak self] regions in
        self?.error = TerrainCorruptionError(regions: regions)
      }
      .store(in: &cancellables)

    // Sync with loader's current state in case a download is already in progress
    handleStateChange(loader.state)
  }

  // MARK: - Public API

  /// Checks if a region is available locally.
  func isAvailable(_ region: TerrainRegion) -> Bool {
    loader.isRegionAvailable(region)
  }

  /// Checks if a region is currently being downloaded (directly, or by the system on the app's
  /// behalf), or holds a payload that a download left unfinished.
  func isDownloading(_ region: TerrainRegion) -> Bool {
    loader.downloadingRegions.contains(region)
      || loader.backgroundDownloadingRegions.contains(region)
      || loader.unfinishedRegions.contains(region)
  }

  /// Returns the status of a region.
  ///
  /// Work in progress outranks corruption, so a region the system is still fetching reads as
  /// downloading even when a previous attempt left it marked corrupt.
  func status(for region: TerrainRegion) -> RegionDownloadStatus {
    if isAvailable(region) {
      return .available
    }
    if isDownloading(region) {
      return .downloading(progress: downloadProgress(for: region))
    }
    if loader.corruptedRegions.contains(region) {
      return .corrupted
    }
    if loader.purgedRegions.contains(region) {
      return .purged
    }
    return .notDownloaded
  }

  /// How far along `region`'s download is, from whichever mechanism is fetching it.
  func downloadProgress(for region: TerrainRegion) -> Float? {
    if case .downloading(let downloadingRegion, let progress) = downloadState,
      downloadingRegion == region
    {
      return progress
    }
    return loader.backgroundDownloadProgress[region].map(Float.init)
  }

  /// Downloads terrain data for a region.
  func downloadRegion(_ region: TerrainRegion) {
    guard !isAvailable(region) && !isDownloading(region) else { return }
    error = nil

    Task {
      do {
        try await loader.downloadRegion(region)
        downloadState = .idle
      } catch {
        if (error as? TerrainDataLoaderError)?.isReportable ?? true {
          SentrySDK.capture(error: error) { scope in
            scope.setTag(value: region.rawValue, key: "terrain.region")
            scope.setTag(value: "download", key: "terrain.operation")
            scope.setFingerprint(["terrain", "download"])
          }
        }
        self.error = error
        downloadState = .idle
      }
    }
  }

  /// Removes a region's terrain data, reclaiming the space it occupies.
  func deleteRegion(_ region: TerrainRegion) {
    error = nil
    Task { await loader.deleteRegion(region) }
  }

  /// Re-downloads a corrupted terrain region, deleting the bad file first.
  func redownloadRegion(_ region: TerrainRegion) {
    error = nil

    Task {
      do {
        try await loader.downloadRegion(region)
        downloadState = .idle
      } catch {
        if (error as? TerrainDataLoaderError)?.isReportable ?? true {
          SentrySDK.capture(error: error) { scope in
            scope.setTag(value: region.rawValue, key: "terrain.region")
            scope.setTag(value: "redownload", key: "terrain.operation")
            scope.setFingerprint(["terrain", "download"])
          }
        }
        self.error = error
        downloadState = .idle
      }
    }
  }

  // MARK: - Private Methods

  private func handleStateChange(_ state: TerrainDataLoader.State) {
    switch state {
      case .idle:
        downloadState = .idle
      case .downloading(let region, let progress):
        downloadState = .downloading(region: region, progress: progress)
      case .completed:
        downloadState = .idle
      case .failed(_, let message):
        downloadState = .idle
        error = TerrainDownloadError(message: message)
    }
  }

  // MARK: - Nested Types

  /// Download state for UI display.
  enum DownloadState: Equatable {
    case idle
    case downloading(region: TerrainRegion, progress: Float?)
  }

  /// Status of a single region.
  enum RegionDownloadStatus: Equatable {

    // MARK: - Cases

    case available
    case corrupted

    /// Downloaded once, then reclaimed by the system for space.
    case purged
    case notDownloaded
    case downloading(progress: Float?)

    // MARK: - Instance Properties

    /// Whether this region holds a payload the user can remove to reclaim its space.
    var hasDeletablePayload: Bool {
      switch self {
        case .available, .corrupted: true
        case .purged, .notDownloaded, .downloading: false
      }
    }
  }
}

/// Error wrapper for terrain download failures.
struct TerrainDownloadError: LocalizedError {
  let message: String

  var errorDescription: String? { message }
}

/// Error surfaced when terrain files on disk are unreadable.
struct TerrainCorruptionError: LocalizedError {
  let regions: Set<TerrainRegion>

  var errorDescription: String? {
    String(localized: "Terrain data couldn’t be loaded.")
  }

  var failureReason: String? {
    let names = regions.map(\.displayName).sorted().formatted(.list(type: .and))
    return String(localized: "The downloaded terrain data for \(names) appears to be corrupted.")
  }

  var recoverySuggestion: String? {
    String(
      localized:
        "Go to Settings → Terrain Data and tap “Re-download” to replace the corrupted files."
    )
  }
}
