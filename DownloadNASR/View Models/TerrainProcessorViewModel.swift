import Foundation
import Logging
import SF50_Shared
import SwiftUI

/// View model coordinating the terrain data processing UI.
///
/// ``TerrainProcessorViewModel`` manages the state for the DownloadNASR tool's terrain
/// processing tab. It coordinates ``SRTMProcessor`` execution and provides observable
/// properties for progress display via a tree of Foundation `Progress` objects.
@Observable
@MainActor
final class TerrainProcessorViewModel {
  /// Whether processing is currently running.
  var isProcessing = false

  /// Current progress (0.0 to 1.0).
  var progress: Double = 0.0

  /// Human-readable status message for current operation.
  var statusMessage = ""

  /// Error message if processing failed.
  var errorMessage: String?

  /// Log entries from the processor for display.
  var logEntries: [LogEntry] = []

  /// Error that occurred during R2 upload, if any.
  var uploadError: Error?

  /// Whether cancellation has been requested but not yet completed.
  var isCancelling = false

  /// Selected regions to process (defaults to all).
  var selectedRegions: Set<TerrainRegion> = Set(TerrainRegion.allCases)

  /// Whether region selection UI is expanded.
  var isRegionSelectionExpanded = false

  /// When the current processing run started (for time-remaining estimates).
  var processingStartDate: Date?

  /// Task handle for cancellation support.
  private var processingTask: Task<Void, Never>?

  /// Reference to the processor actor.
  private var processor: SRTMProcessor?

  /// Regions currently being processed (sorted for consistent index lookup).
  private var processingRegions: [TerrainRegion] = []

  // MARK: - Progress Tree

  /// Root progress object for the entire run.
  private var overallProgress: Progress?

  /// Per-region processing children (download → parse → compress).
  private var regionProgress: [TerrainRegion: Progress] = [:]

  /// Per-region upload children. The `nil` key holds the manifest upload child.
  private var uploadProgress: [TerrainRegion?: Progress] = [:]

  /// Manifest generation child.
  private var manifestProgress: Progress?

  /// Intermediate parent for all region processing children.
  private var processingParent: Progress?

  /// Intermediate parent for all upload children.
  private var uploadParent: Progress?

  /// KVO observation on the root's `fractionCompleted`.
  private var progressObservation: NSKeyValueObservation?

  /// Whether to show the progress bar UI.
  var showProgressBar: Bool {
    (isProcessing || !statusMessage.isEmpty) && errorMessage == nil
  }

  // MARK: - Region Selection

  /// Selects all regions.
  func selectAllRegions() {
    selectedRegions = Set(TerrainRegion.allCases)
  }

  /// Deselects all regions.
  func selectNoRegions() {
    selectedRegions = []
  }

  /// Toggles selection state for a region.
  func toggleRegion(_ region: TerrainRegion) {
    if selectedRegions.contains(region) {
      selectedRegions.remove(region)
    } else {
      selectedRegions.insert(region)
    }
  }

  /// Returns a binding for whether a region is selected.
  func bindingForRegion(_ region: TerrainRegion) -> Binding<Bool> {
    Binding(
      get: { self.selectedRegions.contains(region) },
      set: { isSelected in
        if isSelected {
          self.selectedRegions.insert(region)
        } else {
          self.selectedRegions.remove(region)
        }
      }
    )
  }

  // MARK: - Time Estimation

  /// Estimated time remaining based on elapsed time and progress fraction.
  func estimatedTimeRemaining() -> Duration? {
    guard let processingStartDate, progress > 0, progress < 1 else { return nil }
    let elapsed = Date.now.timeIntervalSince(processingStartDate)
    let totalEstimate = elapsed / progress
    let remaining = totalEstimate - elapsed
    return .seconds(remaining)
  }

  // MARK: - Processing

  /// Starts processing selected regions, outputting to the specified URL.
  func process(outputURL: URL) {
    // Cancel any existing task
    processingTask?.cancel()
    progressObservation?.invalidate()

    // Reset state
    isProcessing = true
    progress = 0.0
    processingStartDate = .now
    statusMessage = String(
      localized: "Starting…",
      comment: "Status message when terrain processing begins"
    )
    errorMessage = nil
    uploadError = nil
    logEntries = []

    // Create logger
    let logger = Logger(label: "codes.tim.SF50-TOLD.DownloadNASR.Terrain")

    // Process selected regions
    let regionsToProcess = Array(selectedRegions).sorted { $0.rawValue < $1.rawValue }
    processingRegions = regionsToProcess

    // Build the Progress tree
    buildProgressTree(for: regionsToProcess)

    // Create processor actor
    let processor = SRTMProcessor(
      regions: regionsToProcess,
      outputLocation: outputURL,
      logger: logger
    )
    self.processor = processor

    // Create progress callback
    let onProgress: @MainActor @Sendable (TerrainProgress) -> Void = { [weak self] state in
      self?.updateFromProgress(state)
    }

    // Create upload error callback
    let onUploadError: @MainActor @Sendable (Error) -> Void = { [weak self] error in
      self?.uploadError = error
    }

    // Create log callback
    let onLog: @MainActor @Sendable (LogEntry) -> Void = { [weak self] entry in
      self?.logEntries.append(entry)
    }

    // Start processing
    processingTask = Task.detached {
      // Set callbacks on processor
      await processor.setCallbacks(
        onProgress: onProgress,
        onUploadError: onUploadError,
        onLog: onLog
      )

      do {
        try await processor.process()

        await MainActor.run { [weak self] in
          self?.statusMessage = String(
            localized: "Complete!",
            comment: "Status message when terrain processing finishes successfully"
          )
          self?.progress = 1.0
        }

        // Reset after a brief delay
        try? await Task.sleep(for: .seconds(2))

        await MainActor.run { [weak self] in
          if !Task.isCancelled { self?.reset() }
        }
      } catch is CancellationError {
        // Task was cancelled - notify processor and reset
        await processor.cancel()
        await MainActor.run { [weak self] in
          self?.reset()
        }
      } catch {
        await MainActor.run { [weak self] in
          self?.errorMessage = error.localizedDescription
          self?.statusMessage = String(
            localized: "Error occurred",
            comment: "Status message when terrain processing fails"
          )
          self?.isProcessing = false
        }
      }
    }
  }

  // MARK: - Progress Tree Construction

  /// Builds the Foundation `Progress` tree for the current run.
  ///
  /// ```
  /// Root (totalUnitCount: 1000)
  /// ├── Processing parent (900 units, totalUnitCount: 10000)
  /// │   └── per-region child weighted by tile count
  /// ├── Manifest generation (10 units, totalUnitCount: 1)
  /// └── Upload parent (90 units, totalUnitCount: numRegions+1)
  ///     ├── per-region upload (1 unit each, totalUnitCount: 100)
  ///     └── manifest upload (1 unit, totalUnitCount: 1)
  /// ```
  private func buildProgressTree(for regions: [TerrainRegion]) {
    let root = Progress(totalUnitCount: 1000)

    // --- Processing parent (90% of overall) ---
    let procParent = Progress(totalUnitCount: 10000)
    root.addChild(procParent, withPendingUnitCount: 900)

    let totalTiles = TerrainRegion.totalTiles(for: regions)
    var regionProgressMap: [TerrainRegion: Progress] = [:]
    for region in regions {
      let weight = region.totalPhaseWeight(totalTiles: totalTiles)
      let child = Progress(totalUnitCount: 10000)
      procParent.addChild(child, withPendingUnitCount: weight)
      regionProgressMap[region] = child
    }

    // --- Manifest generation (1% of overall) ---
    let manifest = Progress(totalUnitCount: 1)
    root.addChild(manifest, withPendingUnitCount: 10)

    // --- Upload parent (9% of overall) ---
    let uplParent = Progress(totalUnitCount: Int64(regions.count + 1))
    root.addChild(uplParent, withPendingUnitCount: 90)

    var uploadProgressMap: [TerrainRegion?: Progress] = [:]
    for region in regions {
      let child = Progress(totalUnitCount: 100)
      uplParent.addChild(child, withPendingUnitCount: 1)
      uploadProgressMap[region] = child
    }
    // Manifest upload child
    let manifestUpload = Progress(totalUnitCount: 1)
    uplParent.addChild(manifestUpload, withPendingUnitCount: 1)
    uploadProgressMap[nil] = manifestUpload

    // Store references
    overallProgress = root
    processingParent = procParent
    regionProgress = regionProgressMap
    manifestProgress = manifest
    uploadParent = uplParent
    uploadProgress = uploadProgressMap

    // KVO on root fractionCompleted → drive self.progress
    progressObservation = root.observe(\.fractionCompleted, options: [.new]) {
      [weak self] progress, _ in
      let fraction = progress.fractionCompleted
      Task { @MainActor [weak self] in
        self?.progress = fraction
      }
    }
  }

  // MARK: - Progress Updates

  /// Translates actor progress state to the appropriate child `Progress` and status message.
  private func updateFromProgress(_ state: TerrainProgress) {
    switch state {
      case .pending:
        statusMessage = String(localized: "Starting…")

      case .downloading(let region, let completed, let total):
        let completedUnits = Int64(
          Double(completed) / Double(max(1, total))
            * Double(TerrainRegion.downloadPhaseRatio)
        )
        regionProgress[region]?.completedUnitCount = completedUnits
        statusMessage = String(
          localized:
            "Downloading \(region.displayName): \(completed, format: .number) of \(total, format: .number)",
          comment: "Status message showing download progress for a terrain region"
        )

      case .parsing(let region, let completed, let total):
        let completedUnits =
          TerrainRegion.downloadPhaseRatio
          + Int64(
            Double(completed) / Double(max(1, total))
              * Double(TerrainRegion.parsePhaseRatio)
          )
        regionProgress[region]?.completedUnitCount = completedUnits
        statusMessage = String(
          localized:
            "Processing \(region.displayName): \(completed, format: .number) of \(total, format: .number)",
          comment: "Status message showing parsing progress for a terrain region"
        )

      case .compressing(let region, let fraction):
        let completedUnits =
          TerrainRegion.downloadPhaseRatio
          + TerrainRegion.parsePhaseRatio
          + Int64(fraction * Double(TerrainRegion.compressPhaseRatio))
        regionProgress[region]?.completedUnitCount = completedUnits
        statusMessage = String(
          localized: "Compressing \(region.displayName)…",
          comment: "Status message when compressing terrain data"
        )

      case .generatingManifest:
        manifestProgress?.completedUnitCount = 1
        statusMessage = String(
          localized: "Generating manifest…",
          comment: "Status message when generating terrain manifest"
        )

      case .uploading(let region, let fraction):
        uploadProgress[region]?.completedUnitCount = Int64(fraction * 100)
        statusMessage = String(
          localized:
            "Uploading \(region.displayName): \(fraction, format: .percent.precision(.fractionLength(1)))",
          comment: "Status message when uploading terrain region to R2"
        )

      case .uploadingManifest:
        uploadProgress[nil]?.completedUnitCount = 1
        statusMessage = String(
          localized: "Uploading manifest…",
          comment: "Status message when uploading terrain manifest to R2"
        )

      case .completed:
        progress = 1.0
        statusMessage = String(
          localized: "Complete!",
          comment: "Status message when terrain processing finishes successfully"
        )

      case .cancelled:
        reset()

      case .failed(let error):
        errorMessage = error.localizedDescription
        isProcessing = false
    }
  }

  /// Resets all state to initial values.
  func reset() {
    progressObservation?.invalidate()
    progressObservation = nil

    isProcessing = false
    isCancelling = false
    progress = 0.0
    processingStartDate = nil
    statusMessage = ""
    errorMessage = nil
    uploadError = nil
    processor = nil
    processingRegions = []

    overallProgress = nil
    processingParent = nil
    regionProgress = [:]
    manifestProgress = nil
    uploadParent = nil
    uploadProgress = [:]
  }

  /// Cancels the current processing task.
  func cancel() {
    isCancelling = true
    processingTask?.cancel()
  }
}
