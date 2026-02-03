import SwiftUI

/// Main content view with tab navigation for nav data and terrain processing.
struct ContentView: View {
  @SwiftUI.State private var selectedTab = 1

  var body: some View {
    TabView(selection: $selectedTab) {
      NavDataView()
        .tabItem {
          Label("Nav Data", systemImage: "airplane.departure")
        }
        .tag(1)

      TerrainView()
        .tabItem {
          Label("Terrain", systemImage: "mountain.2")
        }
        .tag(2)
    }
    .frame(width: 600)
  }
}

#Preview {
  ContentView()
    .frame(height: 700)
}
