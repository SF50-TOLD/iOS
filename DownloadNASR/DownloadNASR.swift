import Logging
import SwiftNASR
import SwiftUI

@main
struct DownloadNASRApp: App {
  var body: some Scene {
    WindowGroup {
      ContentView()
    }

    Settings {
      SettingsView()
    }
  }

  nonisolated init() {
    // Configure default log level
    LoggingSystem.bootstrap { label in
      var handler = StreamLogHandler.standardOutput(label: label)
      handler.logLevel = .notice
      return handler
    }

    // Check for headless mode
    if HeadlessProcessor.shouldRunHeadless() {
      Task {
        let exitCode = await HeadlessProcessor.run()
        exit(exitCode)
      }
      // Keep run loop alive during async processing
      RunLoop.main.run()
    }
  }
}
