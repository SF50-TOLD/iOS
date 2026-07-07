import Foundation
import Logging
import NavDataGeneration
import SwiftNASR

/// Actor that collects log entries from any thread and provides them to the UI.
actor LogCollector {
  private var entries: [LogEntry] = []
  private var continuation: AsyncStream<LogEntry>.Continuation?

  /// Stream of log entries for UI consumption.
  var stream: AsyncStream<LogEntry> {
    AsyncStream { continuation in
      self.continuation = continuation
      continuation.onTermination = { _ in
        Task { await self.clearContinuation() }
      }
    }
  }

  private func clearContinuation() {
    continuation = nil
  }

  /// Add a log entry (called from LogHandler on any thread).
  func add(_ entry: LogEntry) {
    entries.append(entry)
    continuation?.yield(entry)
  }
}

/// LogHandler that sends entries to a LogCollector actor.
private struct ActorLogHandler: LogHandler {
  let collector: LogCollector
  var logLevel: Logger.Level = .notice
  var metadata: Logger.Metadata = [:]

  func log(event: LogEvent) {
    guard event.level >= logLevel else { return }

    var mergedMetadata = self.metadata
    if let eventMetadata = event.metadata {
      mergedMetadata.merge(eventMetadata) { _, new in new }
    }

    // Convert Logger.Metadata to [String: String] for Sendable conformance
    let sendableMetadata: [String: String]? =
      mergedMetadata.isEmpty ? nil : mergedMetadata.mapValues { "\($0)" }

    let entry = LogEntry(
      timestamp: Date(),
      level: event.level,
      message: event.message.description,
      metadata: sendableMetadata
    )

    Task {
      await collector.add(entry)
    }
  }

  subscript(metadataKey key: String) -> Logger.Metadata.Value? {
    get { metadata[key] }
    set { metadata[key] = newValue }
  }
}

/// View model coordinating the airport data processing UI.
///
/// ``NavDataProcessorViewModel`` manages the state for the DownloadNASR tool's main
/// interface. It coordinates ``NavDataProcessor`` execution and provides observable
/// properties for progress display.
///
/// ## Usage
///
/// ```swift
/// @State private var viewModel = ProcessorViewModel()
///
/// viewModel.process(cycle: .current, outputURL: downloadsURL)
/// ```
@Observable
@MainActor
class NavDataProcessorViewModel {
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

  /// Error that occurred during GitHub upload, if any.
  var uploadError: NSError?

  /// Whether cancellation has been requested but not yet completed.
  var isCancelling = false

  /// Task handle for cancellation support.
  private var processingTask: Task<Void, Never>?

  /// Progress object stays on MainActor - never crosses boundaries.
  private var progressObject: Progress?

  /// Observation for progress updates.
  private var progressObservation: NSKeyValueObservation?

  /// Whether to show the progress bar UI.
  var showProgressBar: Bool {
    (isProcessing || !statusMessage.isEmpty) && errorMessage == nil
  }

  /// Starts processing for the given AIRAC cycle, outputting to the specified URL.
  func process(cycle: Cycle, outputURL: URL) {
    // Cancel any existing task
    processingTask?.cancel()
    progressObservation?.invalidate()

    // Reset state
    isProcessing = true
    progress = 0.0
    statusMessage = String(localized: "Starting…", comment: "Status message when processing begins")
    errorMessage = nil
    uploadError = nil
    logEntries = []

    // Create Progress on MainActor - it stays here
    let progressObj = Progress(totalUnitCount: 100)
    self.progressObject = progressObj

    // Observe progress changes (KVO callbacks hop to MainActor)
    self.progressObservation = progressObj.observe(\.fractionCompleted, options: [.new]) {
      [weak self] progress, _ in
      let fraction = progress.fractionCompleted
      let description = progress.localizedDescription ?? ""
      Task { @MainActor [weak self] in
        self?.progress = fraction
        self?.statusMessage = description
      }
    }

    // Create log collector actor
    let logCollector = LogCollector()

    // Subscribe to log entries
    Task { [weak self] in
      for await entry in await logCollector.stream {
        self?.logEntries.append(entry)
      }
    }

    // Create logger with actor-based handler
    let logger = Logger(label: "codes.tim.SF50-TOLD.DownloadNASR") { _ in
      var handler = ActorLogHandler(collector: logCollector)
      handler.logLevel = .notice
      return handler
    }

    // Callbacks for progress updates - these update the MainActor Progress object.
    // Generation reports 0–100; map it onto 0–93 so the upload phase occupies 93–100.
    let onProgress: @MainActor @Sendable (Int64, String) -> Void = {
      [weak self] completed, description in
      self?.progressObject?.completedUnitCount = Int64(Double(completed) * 0.93)
      self?.progressObject?.localizedDescription = description
    }

    processingTask = Task.detached {
      do {
        var processor = NavDataProcessor(
          cycle: cycle,
          outputLocation: outputURL,
          logger: logger
        )
        processor.onProgress = onProgress

        let file = try await processor.process()

        // Upload to GitHub (best-effort); drives the progress bar from 93 → 100.
        await MainActor.run { [weak self] in
          self?.progressObject?.completedUnitCount = 93
          self?.progressObject?.localizedDescription = String(localized: "Uploading to GitHub…")
        }
        if let uploadError = await NavDataUploader(cycle: cycle, logger: logger).upload(file: file)
        {
          await MainActor.run { [weak self] in self?.uploadError = uploadError }
        }
        await MainActor.run { [weak self] in
          self?.progressObject?.completedUnitCount = 100
        }

        await MainActor.run { [weak self] in
          self?.statusMessage = String(
            localized: "Complete!",
            comment: "Status message when processing finishes successfully"
          )
          self?.progress = 1.0
        }

        // Reset after a brief delay
        try? await Task.sleep(for: .seconds(2))

        await MainActor.run { [weak self] in
          if !Task.isCancelled { self?.reset() }
        }
      } catch is CancellationError {
        // Task was cancelled - log and reset
        await logCollector.add(
          LogEntry(
            timestamp: Date(),
            level: .warning,
            message: String(localized: "Processing cancelled by user"),
            metadata: nil
          )
        )
        await MainActor.run { [weak self] in
          self?.reset()
        }
      } catch {
        await MainActor.run { [weak self] in
          self?.errorMessage = error.localizedDescription
          self?.statusMessage = String(
            localized: "Error occurred",
            comment: "Status message when processing fails"
          )
          self?.isProcessing = false
        }
      }
    }
  }

  /// Resets all state to initial values.
  func reset() {
    isProcessing = false
    isCancelling = false
    progress = 0.0
    statusMessage = ""
    errorMessage = nil
    uploadError = nil
  }

  /// Cancels the current processing task.
  func cancel() {
    isCancelling = true
    processingTask?.cancel()
  }
}
