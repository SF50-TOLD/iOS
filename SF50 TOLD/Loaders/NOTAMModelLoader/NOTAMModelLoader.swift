import BackgroundAssets
import Defaults
import Foundation
import NOTAMModel
import NOTAMModelRuntime
import Observation
import SF50_Shared
import Sentry
import System
import os

/// Delivers the on-device NOTAM model and loads it for reading.
///
/// The model arrives as a managed asset pack (`NOTAMModelPack`) the system prefetches; the
/// downloader extension skips it silently when the device is short of space or the pilot deleted
/// it. Everything here fails quietly into "no model": formatted reports are still read by the
/// parsers, and every other NOTAM is entered by hand, exactly as without the model. Only Settings
/// shows why the model isn't there.
///
/// In debug builds, the `NOTAM_MODEL_FOLDER` environment variable names a local model folder to
/// load instead of the pack, so the model can be tried before a pack is published.
@MainActor
@Observable
final class NOTAMModelLoader {

  // MARK: - Type Properties

  static let shared = NOTAMModelLoader()

  nonisolated private static let developmentFolderVariable = "NOTAM_MODEL_FOLDER"

  // MARK: - Instance Properties

  /// Where the model stands.
  private(set) var state: State = .absent

  /// The pack's download size in bytes, once the manifest names it.
  private(set) var downloadSize: Int?

  private var isDownloading: Bool {
    if case .downloading = state { true } else { false }
  }

  @ObservationIgnored private let logger = Logger(
    subsystem: "codes.tim.SF50-TOLD",
    category: "NOTAMModelLoader"
  )
  @ObservationIgnored private var loadedReader: NOTAMModelReader?
  @ObservationIgnored private var readerTask: Task<NOTAMModelReader?, Never>?
  @ObservationIgnored private var statusTask: Task<Void, Never>?

  // MARK: - Initializers

  private init() {
    observePackDownloads()
    refresh()
  }

  // MARK: - Instance Methods

  /// The loaded model, loading it first if the pack is installed and intact; `nil` otherwise.
  func reader() async -> NOTAMModelReader? {
    if let loadedReader { return loadedReader }
    if let readerTask { return await readerTask.value }
    let task = Task { await loadReader() }
    readerTask = task
    let reader = await task.value
    readerTask = nil
    loadedReader = reader
    return reader
  }

  /// Brings ``state`` up to date with what's installed, as on every return to the foreground.
  func refresh() {
    Task {
      let isInstalled = await installedFolder() != nil
      updateState(isInstalled: isInstalled)
      await updateDownloadSize()
    }
  }

  /// Downloads the model now, as the pilot asked from Settings.
  func download() async {
    Defaults[.notamModelDeclined] = false
    state = .downloading(fraction: 0)
    do {
      let manager = AssetPackManager.shared
      _ = try? await manager.checkForUpdates()
      guard let pack = try await manager.manifest.assetPack(withID: NOTAMModelPack.id) else {
        state = .unavailable(.notPublished)
        return
      }
      guard
        NOTAMModelPack.shouldPrefetch(
          isDeclined: false,
          availableCapacity: NOTAMModelPack.availableCapacity(),
          downloadSize: pack.downloadSize
        )
      else {
        state = .unavailable(.insufficientSpace)
        return
      }
      try await manager.ensureLocalAvailability(of: pack, requireLatestVersion: true)
      state = .installed
      _ = await reader()
    } catch {
      state = .unavailable(error.isOutOfDiskSpace ? .insufficientSpace : .downloadFailed)
      if !error.isOutOfDiskSpace { SentrySDK.capture(error: error) }
    }
  }

  /// Deletes the model and keeps the system from fetching it again, as the pilot asked from
  /// Settings.
  func delete() async {
    Defaults[.notamModelDeclined] = true
    readerTask?.cancel()
    readerTask = nil
    loadedReader = nil
    do {
      try await AssetPackManager.shared.remove(assetPackWithID: NOTAMModelPack.id)
    } catch {
      logger.warning("Couldn’t remove the NOTAM model pack: \(error.localizedDescription)")
    }
    state = .declined
  }

  private func updateState(isInstalled: Bool) {
    guard !isDownloading else { return }
    if NOTAMModelPack.isDeclined {
      state = .declined
    } else if !isInstalled {
      state = .absent
    } else if case .unavailable(.damaged) = state {
      return
    } else {
      state = loadedReader == nil ? .installed : .ready
    }
  }

  private func updateDownloadSize() async {
    downloadSize = try? await AssetPackManager.shared.manifest.assetPack(withID: NOTAMModelPack.id)?
      .downloadSize
  }

  /// Follows the system's downloads of the pack, prefetches included.
  private func observePackDownloads() {
    statusTask = Task { [weak self] in
      for await update in AssetPackManager.shared.statusUpdates(
        forAssetPackWithID: NOTAMModelPack.id
      ) {
        if Task.isCancelled { break }
        self?.apply(update)
      }
    }
  }

  private func apply(_ update: AssetPackManager.DownloadStatusUpdate) {
    switch update {
      case .began, .paused:
        state = .downloading(fraction: 0)
      case .downloading(_, let progress):
        state = .downloading(fraction: progress.fractionCompleted)
      case .finished:
        state = .installed
      case .failed(_, let error):
        logger.notice("NOTAM model download failed: \(error.localizedDescription)")
        state = .unavailable(error.isOutOfDiskSpace ? .insufficientSpace : .downloadFailed)
      @unknown default:
        break
    }
  }

  /// Where the installed model folder is, or `nil` when there isn't one.
  ///
  /// `url(for:)` answers with a path whether or not anything is behind it, so installation is asked
  /// of the manager and the model's manifest is checked for as well. The manager can block while it
  /// answers, so this runs off the main actor.
  @concurrent
  nonisolated private func installedFolder() async -> URL? {
    #if DEBUG
      if let path = ProcessInfo.processInfo.environment[Self.developmentFolderVariable] {
        return URL(filePath: path)
      }
    #endif
    let manager = AssetPackManager.shared
    guard manager.assetPackIsAvailableLocally(withID: NOTAMModelPack.id),
      let folder = try? manager.url(for: FilePath(NOTAMModelPack.folderPath)),
      FileManager.default.fileExists(atPath: folder.appending(path: "notam-model.json").path)
    else { return nil }
    return folder
  }

  private func loadReader() async -> NOTAMModelReader? {
    guard !NOTAMModelPack.isDeclined, let folder = await installedFolder() else { return nil }
    state = .verifying
    guard await isIntact(folder) else {
      state = .unavailable(.damaged)
      return nil
    }
    do {
      let reader = try await NOTAMModelReader(folder: folder)
      state = .ready
      return reader
    } catch {
      logger.error("Couldn’t load the NOTAM model: \(String(describing: error))")
      SentrySDK.capture(error: error)
      state = .unavailable(.unloadable)
      return nil
    }
  }

  private func isIntact(_ folder: URL) async -> Bool {
    #if DEBUG
      if ProcessInfo.processInfo.environment[Self.developmentFolderVariable] != nil { return true }
    #endif
    return await Task.detached(priority: .utility) {
      (try? NOTAMModelVerifier().isIntact(folderAt: folder)) ?? false
    }.value
  }

  // MARK: - Nested Types

  /// Where the model stands on this device.
  enum State: Equatable {
    /// Not downloaded, and not asked for.
    case absent
    /// The system is downloading it.
    case downloading(fraction: Double)
    /// On disk, not yet loaded.
    case installed
    /// On disk and being checked against its digest.
    case verifying
    /// Loaded and reading NOTAMs.
    case ready
    /// The pilot deleted it; it won't be fetched again until they download it.
    case declined
    /// It can't be used, for the given reason.
    case unavailable(Problem)
  }

  /// Why the model can't be used.
  enum Problem: Equatable {
    /// No model has been published for this app yet.
    case notPublished
    /// The device lacks room for it.
    case insufficientSpace
    /// Downloading it failed.
    case downloadFailed
    /// Its files don't match the digest it was published with.
    case damaged
    /// It couldn't be loaded on this device.
    case unloadable
  }
}
