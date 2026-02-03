import Logging
import SwiftNASR
import SwiftUI

@main
struct DownloadNASRApp: App {
  @SwiftUI.State private var missingCredentials: [String] = []

  var body: some Scene {
    WindowGroup {
      ContentView()
        .alert("Missing Credentials", isPresented: .constant(!missingCredentials.isEmpty)) {
          Button("Quit") { NSApplication.shared.terminate(nil) }
        } message: {
          Text(
            """
            Configure these in Credentials.xcconfig:
            \(missingCredentials, format: .list(type: .and))

            See GettingStarted.md for instructions.
            """
          )
        }
        .task { missingCredentials = CredentialsConfig.validateRequired() }
    }
    .windowResizability(.contentSize)
  }

  nonisolated init() {
    // Configure default log level
    LoggingSystem.bootstrap { label in
      var handler = StreamLogHandler.standardOutput(label: label)
      handler.logLevel = .notice
      return handler
    }

    // Check for headless modes (NASR takes priority if both set)
    if NavDataHeadlessProcessor.shouldRunHeadless() {
      Task {
        let exitCode = await NavDataHeadlessProcessor.run()
        exit(exitCode)
      }
      // Keep run loop alive during async processing
      RunLoop.main.run()
    } else if TerrainHeadlessProcessor.shouldRunHeadless() {
      Task {
        let exitCode = await TerrainHeadlessProcessor.run()
        exit(exitCode)
      }
      RunLoop.main.run()
    }
  }
}
