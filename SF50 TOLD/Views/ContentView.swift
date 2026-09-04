import Defaults
import Foundation
import SF50_Shared
import SwiftData
import SwiftUI

struct ContentView: View {
  @Default(.initialSetupComplete)
  private var initialSetupComplete

  @Default(.aircraftTypeSetting)
  private var aircraftTypeSetting

  @State private var tab = 1
  @State private var loader: NavDataLoaderViewModel?

  @Environment(\.modelContext)
  private var context

  var body: some View {
    AircraftTypeProvider {
      content
    }
    .onAppear {
      if loader == nil {
        loader = .init(container: context.container)
      }
    }
    .environment(\.pathAtmosphereLoader, UITestingHelper.pathAtmosphereLoader)
    .modifier(UITestLocationStreamer())
  }

  @ViewBuilder private var content: some View {
    if !initialSetupComplete || aircraftTypeSetting == nil {
      WelcomeView()
    } else if loader?.showLoader != false {
      if let loader {
        LoadingView()
          .environment(loader)
      } else {
        ProgressView()
      }
    } else {
      TabView(selection: $tab) {
        TakeoffView().tabItem {
          Label("Takeoff", systemImage: "airplane.departure")
        }
        .tag(1)

        ClimbView().tabItem {
          Label("Climb", systemImage: "arrow.up.right")
        }
        .tag(2)

        LandingView().tabItem {
          Label("Landing", systemImage: "airplane.arrival")
        }
        .tag(3)

        SettingsView().tabItem {
          Label("Settings", systemImage: "gear")
        }
        .tag(4)

        AboutView().tabItem {
          Label("About", systemImage: "info.circle")
        }
        .tag(5)
      }
      .tapToDismissKeyboard()
      .accessibilityIdentifier("mainTabView")
    }
  }
}

/// Substitutes a scripted location source when a UI test supplies one.
///
/// Outside UI testing nothing is injected and the environment default stands, which builds a
/// real streamer only when something first reads it.
private struct UITestLocationStreamer: ViewModifier {
  func body(content: Content) -> some View {
    if let streamer = UITestingHelper.locationStreamer {
      content.environment(\.locationStreamer, streamer)
    } else {
      content
    }
  }
}

#Preview {
  ContentView()
}
