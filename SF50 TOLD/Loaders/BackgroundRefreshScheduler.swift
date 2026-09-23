import BackgroundTasks
import Defaults
import Foundation
import SF50_Shared
import SwiftData
import os

/// Coordinates the work the app does while it is not on screen, so a returning pilot finds warm
/// weather and current airport data.
///
/// Two tasks run here, each registered declaratively by a scene modifier on `SF50_TOLDApp` and
/// submitted by this scheduler:
///
/// - An **app refresh** pre-warms `WeatherLoader`'s bulk caches. iOS budgets these by habit, Low
///   Power Mode and the Background App Refresh setting, and gives each a short window.
/// - A **processing task** replaces the airport data once its cycle has lapsed. An update runs for
///   minutes, far longer than an app refresh allows, so it asks for the long window iOS grants a
///   device on its charger with a network. It never runs before the pilot's first load, and keeps
///   to networks iOS does not treat as metered unless the pilot has allowed them.
///
/// Neither is guaranteed to run. Both are an optimization over the on-launch path, which still
/// warms the weather and still offers the pilot any update the background did not get to.
@MainActor
final class BackgroundRefreshScheduler {
  /// Shared singleton owning background-refresh scheduling.
  static let shared = BackgroundRefreshScheduler()

  /// The app-refresh task identifier, matched by the Info.plist
  /// `BGTaskSchedulerPermittedIdentifiers` array and the
  /// `.backgroundTask(.appRefresh(_:))` scene modifier.
  static let appRefreshIdentifier = "codes.tim.SF50-TOLD.refresh"

  /// The processing-task identifier for replacing lapsed airport data, matched by the Info.plist
  /// `BGTaskSchedulerPermittedIdentifiers` array and the
  /// `.backgroundTask(.processingTask(_:))` scene modifier.
  static let navDataRefreshIdentifier = "codes.tim.SF50-TOLD.navdata-processing"

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

  /// The networks a background update may use: those iOS does not treat as metered, and metered
  /// ones too once the pilot has allowed them.
  private var backgroundNetworkAccess: NavDataNetworkAccess {
    Defaults[.allowsBackgroundMeteredDownloads] ? .any : .unmeteredOnly
  }

  private init() {}

  /// Plans the refresh from the generation of airport data active on disk.
  ///
  /// The app's own container can still be reading a generation an earlier background update
  /// replaced — it reopens only while its scene is running — and a plan read from it would find the
  /// replaced data stale and download it again. This opens the active generation itself, away from
  /// the main actor.
  ///
  /// - Returns: The plan, or ``NavDataRefreshPlan/none`` when no generation is installed.
  @concurrent
  nonisolated private static func planFromActiveGeneration() async throws -> NavDataRefreshPlan {
    let container: ModelContainer
    do {
      container = try AppStore.makeContainerForExistingGeneration(
        layout: .appGroup,
        generation: Defaults[.activeNavDataGeneration]
      )
    } catch AppStore.Errors.navDataStoreIsMissing {
      return .none
    }
    return NavDataRefreshPlan(try NavDataStateHelper.fetchState(context: ModelContext(container)))
  }

  /// Submits a fresh app-refresh request so iOS can schedule the next refresh.
  ///
  /// Transient scheduling failures (`notPermitted`, `tooManyPendingTaskRequests`)
  /// are logged locally only and never reported to Sentry as errors, matching the
  /// app's policy of not surfacing transient background failures.
  func scheduleAppRefresh() async {
    guard isEnabled else { return }

    let request = BGAppRefreshTaskRequest(identifier: Self.appRefreshIdentifier)
    request.earliestBeginDate = Date(timeIntervalSinceNow: Self.minimumRefreshInterval)
    await submit(request, describing: "background app refresh")
  }

  /// Orchestrates the app-refresh action: reschedules, then pre-warms weather.
  ///
  /// SwiftUI marks the underlying `BGTask` complete when this returns and cancels
  /// the backing Swift `Task` on expiration. That cancellation is forwarded to the
  /// weather loader, so an in-flight fetch is abandoned at the deadline instead of
  /// overrunning the refresh window.
  func handleAppRefresh() async {
    guard isEnabled else { return }

    await scheduleAppRefresh()
    await prewarmWeather()
  }

  /// Submits a processing request to replace the airport data once its cycle lapses.
  ///
  /// The request needs external power and a network, and starts no earlier than the moment the
  /// installed NASR cycle expires. Data already out of date asks to start as soon as iOS allows,
  /// and a device with no data installed submits nothing.
  func scheduleNavDataRefresh() async {
    guard isEnabled else { return }

    let plan: NavDataRefreshPlan
    do { plan = try await Self.planFromActiveGeneration() } catch {
      logger.notice("Couldn’t plan a nav-data refresh: \(error.localizedDescription)")
      return
    }

    let request = BGProcessingTaskRequest(identifier: Self.navDataRefreshIdentifier)
    request.requiresNetworkConnectivity = true
    request.requiresExternalPower = true
    switch plan {
      case .none: return
      case .now: request.earliestBeginDate = nil
      case .at(let expires): request.earliestBeginDate = expires
    }
    await submit(request, describing: "nav-data refresh")
  }

  /// Replaces the airport data if it has lapsed, then schedules the next refresh.
  ///
  /// SwiftUI marks the underlying `BGTask` complete when this returns and cancels the backing Swift
  /// `Task` on expiration. That cancellation stops the update, which leaves nothing behind but a
  /// generation the next launch reclaims: the data in use is only replaced once the new data is
  /// whole.
  func handleNavDataRefresh() async {
    guard isEnabled else { return }

    do {
      guard try await Self.planFromActiveGeneration() == .now else {
        logger.debug("Nav data is current; nothing to refresh.")
        await scheduleNavDataRefresh()
        return
      }
      try await NavDataUpdater.shared.update(
        container: AppStore.shared,
        networkAccess: backgroundNetworkAccess
      )
      logger.notice("Replaced the airport data in the background.")
    } catch {
      logger.notice("Background nav-data refresh stopped: \(error.localizedDescription)")
    }
    await scheduleNavDataRefresh()
  }

  /// Submits a background task request, logging rather than reporting a refusal.
  ///
  /// A request for a task already pending replaces it.
  private func submit(_ request: BGTaskRequest, describing description: String) async {
    do {
      try await BGTaskScheduler.shared.submitTaskRequest(request)
      logger.debug("Scheduled \(description, privacy: .public).")
    } catch {
      logger.notice(
        "Could not schedule \(description, privacy: .public): \(error.localizedDescription)"
      )
    }
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
}
