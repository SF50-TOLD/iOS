import Combine
import Foundation
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
  var error: Error?

  /// The underlying terrain data loader.
  private let loader = TerrainDataLoader()

  /// Cancellables for Combine subscriptions.
  private var cancellables = Set<AnyCancellable>()

  /// Total size of downloaded terrain data in bytes.
  var totalDownloadedSize: Int64 {
    allRegions
      .filter { isAvailable($0) }
      .reduce(0) { $0 + Int64($1.sizeBytes) }
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

    loader.$decompressingRegions
      .sink { [weak self] _ in
        self?.objectWillChange.send()
      }
      .store(in: &cancellables)
  }

  // MARK: - Public API

  /// Checks if a region is available locally.
  func isAvailable(_ region: TerrainRegion) -> Bool {
    loader.isRegionAvailable(region)
  }

  /// Checks if a region is currently being downloaded (directly or via Background Assets).
  func isDownloading(_ region: TerrainRegion) -> Bool {
    loader.downloadingRegions.contains(region)
      || loader.backgroundDownloadingRegions.contains(region)
  }

  /// Returns the status of a region.
  func status(for region: TerrainRegion) -> RegionDownloadStatus {
    if isAvailable(region) {
      return .available
    }
    if isDownloading(region) {
      if case .downloading(let r, let progress) = downloadState, r == region {
        return .downloading(progress: progress)
      }
      return .downloading(progress: nil)
    }
    if loader.decompressingRegions.contains(region) {
      return .downloading(progress: nil)
    }
    return .notDownloaded
  }

  /// Downloads terrain data for a region.
  func downloadRegion(_ region: TerrainRegion) {
    guard !isAvailable(region) && !isDownloading(region) else { return }

    Task {
      do {
        try await loader.downloadRegion(region)
        downloadState = .idle
      } catch {
        self.error = error
        downloadState = .idle
      }
    }
  }

  /// Checks if terrain is available for an airport coordinate.
  func terrainStatus(for latitude: Double, longitude: Double) -> TerrainAvailability {
    switch loader.regionStatus(for: (latitude, longitude)) {
      case .available(let region):
        return .available(region: region)
      case .needsDownload(let region):
        return .needsDownload(region: region)
      case .downloading(let region):
        return .downloading(region: region)
      case .notCovered:
        return .notCovered
    }
  }

  /// Refreshes the list of available regions and active BA downloads.
  func refresh() {
    loader.refreshAvailableRegions()
    loader.refreshBackgroundDownloads()
  }

  /// Returns the terrain file URL for a region, if available.
  func terrainFileURL(for region: TerrainRegion) -> URL? {
    loader.terrainFileURL(for: region)
  }

  // MARK: - Private Methods

  private func handleStateChange(_ state: TerrainDataLoader.State) {
    switch state {
      case .idle:
        downloadState = .idle
      case .downloading(let region, let progress):
        downloadState = .downloading(region: region, progress: progress)
      case .decompressing(let region):
        downloadState = .decompressing(region: region)
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
    case decompressing(region: TerrainRegion)
  }

  /// Status of a single region.
  enum RegionDownloadStatus: Equatable {
    case available
    case notDownloaded
    case downloading(progress: Float?)
  }

  /// Terrain availability for a location.
  enum TerrainAvailability: Equatable {
    case available(region: TerrainRegion)
    case needsDownload(region: TerrainRegion)
    case downloading(region: TerrainRegion)
    case notCovered
  }
}

/// Error wrapper for terrain download failures.
struct TerrainDownloadError: LocalizedError {
  let message: String

  var errorDescription: String? { message }
}

// MARK: - Preview Support

extension TerrainDataLoaderViewModel {
  /// Creates a preview instance with mocked state.
  static func preview(
    availableRegions _: Set<TerrainRegion> = [.northAmerica],
    downloadingRegion _: TerrainRegion? = nil
  ) -> TerrainDataLoaderViewModel {
    // In preview, we ca/n't easily mock the loader state
    // The view should handle this gracefully
    return TerrainDataLoaderViewModel()
  }
}
