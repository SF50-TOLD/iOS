import BackgroundTasks
import Foundation
import os

/// Keeps a nav-data import running after the pilot leaves the app.
///
/// An import takes minutes, and until now the consent screen had to ask that the app be left open,
/// because a plain `Task` gets seconds of runtime once the app is backgrounded and the transfer
/// would restart from nothing. A continued-processing task buys that time, and gives the system a
/// progress and cancel affordance the app does not have to draw.
///
/// This is only safe now that an import writes a generation nothing is reading. The system expires
/// these tasks on changing conditions, and cancels them outright when the app is swiped out of the
/// switcher, **without telling the app** — against an import that emptied the live dataset first,
/// that meant an empty airport database.
///
/// Failing to get a task is not an error. The import runs either way; it just runs unprotected, as
/// it always did.
@MainActor
final class NavDataDownloadTask {
  /// The identifier this task is registered and submitted under.
  ///
  /// One fixed string, advertised verbatim in `BGTaskSchedulerPermittedIdentifiers`. A handler has
  /// to be registered while launching, so the identifier it answers for has to be known then —
  /// which rules out naming each submission after the import it belongs to.
  static let identifier = "codes.tim.SF50-TOLD.navdata-download"

  /// The shared task broker.
  static let shared = NavDataDownloadTask()

  private let logger = Logger(
    subsystem: "codes.tim.SF50-TOLD",
    category: "NavDataDownloadTask"
  )

  private var isRegistered = false

  /// Resumed when the system hands over a task, carrying nothing: `BGContinuedProcessingTask` is
  /// not `Sendable`, and it never has to leave this actor to be handed back.
  private var pendingStart: CheckedContinuation<Void, Never>?
  private var startedTask: BGContinuedProcessingTask?

  /// Whether a background task should be asked for at all.
  ///
  /// Inert under UI testing and screenshot generation, so XCTest's wait-for-idle never stalls on
  /// system-owned work and no request is submitted during a test run.
  private var isEnabled: Bool {
    let arguments = ProcessInfo.processInfo.arguments
    return !arguments.contains("UI-TESTING") && !arguments.contains("GENERATE-SCREENSHOTS")
  }

  private init() {}

  /// Registers the launch handler.
  ///
  /// Called while the app is launching, as every other task identifier here is. Registering later
  /// is refused — the permitted identifiers are read once, and a handler offered afterwards is not
  /// matched against them.
  func registerHandler() {
    guard isEnabled, !isRegistered else { return }

    isRegistered = BGTaskScheduler.shared.register(
      forTaskWithIdentifier: Self.identifier,
      using: .main
    ) { [weak self] task in
      MainActor.assumeIsolated {
        guard let continuedProcessing = task as? BGContinuedProcessingTask else {
          task.setTaskCompleted(success: false)
          return
        }
        self?.start(continuedProcessing)
      }
    }

    if !isRegistered {
      logger.error(
        "Couldn’t register \(Self.identifier, privacy: .public); is it permitted in Info.plist?"
      )
    }
  }

  /// Asks the system to let the import keep running when the app is backgrounded.
  ///
  /// - Parameters:
  ///   - title: What the system should call this work.
  ///   - subtitle: The phase to show beneath it.
  /// - Returns: The task to report progress to, or `nil` if the system would not start one — in
  ///   which case the caller carries on unprotected.
  func begin(title: String, subtitle: String) async -> BGContinuedProcessingTask? {
    guard isEnabled, isRegistered else { return nil }

    let request = BGContinuedProcessingTaskRequest(
      identifier: Self.identifier,
      title: title,
      subtitle: subtitle
    )
    // Start now or not at all: a queued request waits on system load, and the import would rather
    // run unprotected than wait to begin.
    request.strategy = .fail

    do {
      try BGTaskScheduler.shared.submit(request)
    } catch {
      logger.notice("Running the import unprotected: \(error.localizedDescription)")
      return nil
    }

    await withCheckedContinuation { continuation in
      pendingStart = continuation
    }
    defer { startedTask = nil }
    return startedTask
  }

  private func start(_ task: BGContinuedProcessingTask) {
    guard let continuation = pendingStart else {
      // Nothing is waiting for this — most likely a request that outlived its import.
      task.setTaskCompleted(success: false)
      return
    }
    pendingStart = nil
    startedTask = task
    continuation.resume()
  }
}
