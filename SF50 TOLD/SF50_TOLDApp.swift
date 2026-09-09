import BackgroundTasks
import Combine
import Defaults
import SF50_Shared
import Sentry
import SwiftData
import SwiftUI
import WidgetKit

// periphery:ignore - side-effect-only observer retained by @StateObject below
private class WidgetReloadObserver: ObservableObject {
  private var notificationObserver: Any?

  init() {
    setupObserver()
  }

  /// Watches for a changed default and asks the widget to redraw.
  ///
  /// The observer names no queue and hands the reload to the main actor itself, so the thread
  /// that posted the notification is never made to wait. An observer bound to a queue is
  /// delivered by making every poster wait for that queue to run it, and the posters include
  /// `registerDefaults(_:)`, which `Defaults` calls from inside a key's one-time initializer:
  /// a background thread first touching a key would hold that initializer while waiting on
  /// the main queue, and a main thread touching the same key would wait on the initializer.
  private func setupObserver() {
    notificationObserver = NotificationCenter.default.addObserver(
      forName: UserDefaults.didChangeNotification,
      object: nil,
      queue: nil
    ) { _ in
      Task { @MainActor in
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.selectedAirportPerformance)
      }
    }
  }

  deinit {
    if let notificationObserver {
      NotificationCenter.default.removeObserver(notificationObserver)
    }
  }
}

@main
struct SF50_TOLDApp: App {
  @State private var sharedModelContainer = Self.makeContainer()
  @State private var navDataGeneration = Defaults[.activeNavDataGeneration]

  // periphery:ignore - side-effect-only observer; retained for its lifetime, never read
  @StateObject private var widgetReloadObserver = WidgetReloadObserver()

  @Environment(\.scenePhase)
  private var scenePhase

  var body: some Scene {
    WindowGroup {
      ContentView()
        .modelContainer(sharedModelContainer)
        .id(navDataGeneration)
        .terrainPurgeAlert()
        .task {
          await ScenarioSeeder(container: sharedModelContainer).seedDefaultScenariosIfNeeded()
          _ = TerrainDataLoader.shared
        }
        .task { await adoptNewNavDataGenerations() }
    }
    .backgroundTask(.appRefresh(BackgroundRefreshScheduler.appRefreshIdentifier)) {
      await BackgroundRefreshScheduler.shared.handleAppRefresh()
    }
    .onChange(of: scenePhase) { _, newPhase in
      switch newPhase {
        case .background: BackgroundRefreshScheduler.shared.scheduleAppRefresh()
        case .active: TerrainDataLoader.shared.refreshAvailableRegions()
        default: break
      }
    }
  }

  init() {
    // Registered while launching: the permitted identifiers are read once, and a handler offered
    // afterwards is not matched against them.
    NavDataDownloadTask.shared.registerHandler()

    if ProcessInfo.processInfo.arguments.contains("UI-TESTING") {
      UITestingHelper.setupUITestingEnvironment()
      // Skip Sentry under UI tests: its profiling registers a CADisplayLink and
      // its logging runs on the main thread, which XCTest treats as never-ending
      // work — stalling wait-for-idle until tests time out (matches FART).
      return
    }

    SentrySDK.start { options in
      options.dsn =
        "https://18ccb9d2342467fafcaebcc33cc676e5@o4510156629475328.ingest.us.sentry.io/4510161674502144"

      options.debug = false

      // There are no accounts here, and the privacy manifest declares diagnostics as not linked to
      // identity — so never attach the user's IP address or other identifying context to an event.
      options.sendDefaultPii = false

      // Set tracesSampleRate to 1.0 to capture 100% of transactions for performance monitoring.
      // We recommend adjusting this value in production.
      options.tracesSampleRate = 1.0

      // Configure profiling. Visit https://docs.sentry.io/platforms/apple/profiling/ to learn more.
      options.configureProfiling = {
        $0.sessionSampleRate = 1.0  // We recommend adjusting this value in production.
        $0.lifecycle = .trace
      }

      // Uncomment the following lines to add more data to your events
      // options.attachScreenshot = true // This adds a screenshot to the error events
      // options.attachViewHierarchy = true // This adds the view hierarchy to the error events

      // Enable logging features
      options.enableLogs = true

      // Discard all events when running on simulator
      options.beforeSend = { event in
        #if targetEnvironment(simulator)
          return nil
        #else
          return event
        #endif
      }
    }
  }

  /// Opens the app's stores, or an in-memory stand-in for a screenshot run.
  private static func makeContainer() -> ModelContainer {
    // Screenshot runs hold their data in memory so the generated shots never depend on, or
    // disturb, whatever is in the group container.
    guard ProcessInfo.processInfo.arguments.contains("GENERATE-SCREENSHOTS") else {
      // Nav data is read-only once the app holds it, so a UI test's airports go in first.
      MainActor.assumeIsolated { UITestingHelper.prepareStores() }
      return AppStore.shared
    }
    do { return try AppStore.makeInMemoryContainer() } catch {
      fatalError("Could not create ModelContainer: \(error)")
    }
  }

  /// Rebuilds the store when an import switches to a newly downloaded generation.
  ///
  /// The container holds an open handle on one generation's file, so a new one only reaches the app
  /// by opening it. The generation it was reading is left on disk until the next launch, when
  /// nothing holds it — which is what makes swapping safe while the app is running.
  private func adoptNewNavDataGenerations() async {
    var isFirstEmission = true
    for await _ in Defaults.updates(.activeNavDataGeneration) {
      guard !isFirstEmission else {
        isFirstEmission = false
        continue
      }
      AppStore.reopen()
      sharedModelContainer = AppStore.shared
      navDataGeneration = Defaults[.activeNavDataGeneration]
    }
  }
}
