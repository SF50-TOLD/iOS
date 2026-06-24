import BackgroundTasks
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

  private func setupObserver() {
    notificationObserver = NotificationCenter.default.addObserver(
      forName: UserDefaults.didChangeNotification,
      object: nil,
      queue: .main
    ) { _ in
      WidgetCenter.shared.reloadTimelines(ofKind: "SF50_SelectedAirport")
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
  var sharedModelContainer: ModelContainer = {
    let schema = Schema([
      Airport.self,
      Runway.self,
      NOTAM.self,
      Scenario.self,
      Cycle.self,
      Obstacle.self,
      Procedure.self,
      ProcedureSegment.self,
      Leg.self,
      Navaid.self
    ])

    // Use in-memory storage for screenshot generation to avoid file access issues
    let isGeneratingScreenshots = ProcessInfo.processInfo.arguments.contains("GENERATE-SCREENSHOTS")
    let modelConfiguration =
      if isGeneratingScreenshots {
        ModelConfiguration(
          schema: schema,
          isStoredInMemoryOnly: true
        )
      } else {
        ModelConfiguration(
          schema: schema,
          isStoredInMemoryOnly: false,
          groupContainer: .identifier("group.codes.tim.TOLD")
        )
      }

    do {
      return try ModelContainer(for: schema, configurations: [modelConfiguration])
    } catch {
      fatalError("Could not create ModelContainer: \(error)")
    }
  }()

  // periphery:ignore - side-effect-only observer; retained for its lifetime, never read
  @StateObject private var widgetReloadObserver = WidgetReloadObserver()

  @Environment(\.scenePhase)
  private var scenePhase

  var body: some Scene {
    WindowGroup {
      ContentView()
        .modelContainer(sharedModelContainer)
        .task {
          await ScenarioSeeder(container: sharedModelContainer).seedDefaultScenariosIfNeeded()
          _ = TerrainDataLoader.shared
        }
    }
    .backgroundTask(.appRefresh(BackgroundRefreshScheduler.appRefreshIdentifier)) {
      await BackgroundRefreshScheduler.shared.handleAppRefresh()
    }
    .onChange(of: scenePhase) { _, newPhase in
      if newPhase == .background {
        BackgroundRefreshScheduler.shared.scheduleAppRefresh()
      }
    }
  }

  init() {
    if ProcessInfo.processInfo.arguments.contains("UI-TESTING") {
      UITestingHelper.setupUITestingEnvironment(container: sharedModelContainer)
      // Skip Sentry under UI tests: its profiling registers a CADisplayLink and
      // its logging runs on the main thread, which XCTest treats as never-ending
      // work — stalling wait-for-idle until tests time out (matches FART).
      return
    }

    SentrySDK.start { options in
      options.dsn =
        "https://18ccb9d2342467fafcaebcc33cc676e5@o4510156629475328.ingest.us.sentry.io/4510161674502144"

      options.debug = false

      // Adds IP for users.
      // For more information, visit: https://docs.sentry.io/platforms/apple/data-management/data-collected/
      options.sendDefaultPii = true

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
}
