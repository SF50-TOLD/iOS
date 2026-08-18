import BackgroundTasks
import Foundation
import SF50_Shared
import os

/// Coordinates best-effort background app-refresh work so returning users find a
/// warmed weather cache before they next open the app.
///
/// The app registers the launch handler declaratively via the
/// `.backgroundTask(.appRefresh(_:))` scene modifier on `SF50_TOLDApp`; this
/// scheduler owns the matching `BGAppRefreshTaskRequest` submission and the
/// refresh action body. Execution is never guaranteed — iOS budgets app-refresh
/// by user habits, Low Power Mode, and the Background App Refresh setting — so
/// this is purely an optimization layered on top of the fully functional
/// on-launch path.
///
/// ## Refresh Work
///
/// The refresh action pre-warms `WeatherLoader`'s bulk caches. Nav-data is
/// intentionally **not** refreshed here: ``NavDataLoader`` deletes the live
/// dataset before re-importing over several minutes, far longer than an
/// app-refresh window, so a mid-window force-cancellation could leave the store
/// empty or partially imported. Nav-data staleness is resolved on the next launch
/// instead.
@MainActor
final class BackgroundRefreshScheduler {
  /// Shared singleton owning background-refresh scheduling.
  static let shared = BackgroundRefreshScheduler()

  /// The app-refresh task identifier, matched by the Info.plist
  /// `BGTaskSchedulerPermittedIdentifiers` array and the
  /// `.backgroundTask(.appRefresh(_:))` scene modifier.
  static let appRefreshIdentifier = "codes.tim.SF50-TOLD.refresh"

  private static let minimumRefreshInterval: TimeInterval = 4 * 60 * 60

  private let logger = Logger(
    subsystem: "codes.tim.SF50-TOLD",
    category: "BackgroundRefresh"
  )

  /// Whether background-refresh work should run.
  ///
  /// Inert under UI testing and screenshot generation so XCTest's wait-for-idle
  /// never stalls on background work and no `BGTaskRequest` is submitted during
  /// a test run.
  private var isEnabled: Bool {
    let arguments = ProcessInfo.processInfo.arguments
    return !arguments.contains("UI-TESTING") && !arguments.contains("GENERATE-SCREENSHOTS")
  }

  private init() {}

  /// Submits a fresh app-refresh request so iOS can schedule the next refresh.
  ///
  /// Transient scheduling failures (`notPermitted`, `tooManyPendingTaskRequests`)
  /// are logged locally only and never reported to Sentry as errors, matching the
  /// app's policy of not surfacing transient background failures.
  func scheduleAppRefresh() {
    guard isEnabled else { return }

    let request = BGAppRefreshTaskRequest(identifier: Self.appRefreshIdentifier)
    request.earliestBeginDate = Date(timeIntervalSinceNow: Self.minimumRefreshInterval)

    do {
      try BGTaskScheduler.shared.submit(request)
      logger.debug("Scheduled background app refresh.")
    } catch {
      logger.notice("Could not schedule background app refresh: \(error.localizedDescription)")
    }
  }

  /// Orchestrates the app-refresh action: reschedules, then pre-warms weather.
  ///
  /// SwiftUI marks the underlying `BGTask` complete when this returns and cancels
  /// the backing Swift `Task` on expiration. That cancellation is forwarded to the
  /// weather loader, so an in-flight fetch is abandoned at the deadline instead of
  /// overrunning the refresh window.
  func handleAppRefresh() async {
    guard isEnabled else { return }

    scheduleAppRefresh()
    await prewarmWeather()
    refreshNavDataIfStale()
  }

  /// Pre-warms ``WeatherLoader``'s caches, forwarding background-task expiration
  /// to the loader so an in-flight fetch is cancelled at the deadline.
  ///
  /// ``WeatherLoader/load(force:)`` runs its network work in a detached task that
  /// does not inherit the caller's cancellation, so expiration is bridged
  /// explicitly via ``WeatherLoader/cancelLoading()``.
  private func prewarmWeather() async {
    logger.debug("Pre-warming weather cache.")
    await withTaskCancellationHandler {
      await WeatherLoader.shared.load()
    } onCancel: {
      Task { await WeatherLoader.shared.cancelLoading() }
    }
  }

  /// Nav-data refresh is deliberately skipped in the app-refresh window.
  ///
  /// ``NavDataLoader/load()`` deletes the live dataset and re-imports over
  /// several minutes — longer than an app-refresh window — and its import
  /// container shares the live persistent store, so a force-cancellation
  /// mid-import could corrupt or empty the store. Refreshing nav data off-launch
  /// safely requires either importing into a genuinely separate store and
  /// atomically swapping it in, or moving the import to a `BGProcessingTask`
  /// (`codes.tim.SF50-TOLD.navdata-processing`, `UIBackgroundModes` `processing`,
  /// `requiresNetworkConnectivity = true`) that gets a longer runtime budget.
  /// Until then, nav-data staleness is resolved on the next launch.
  private func refreshNavDataIfStale() {
    logger.debug("Skipping nav-data refresh in app-refresh window (handled on launch).")
  }
}
