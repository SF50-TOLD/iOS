import SF50_Shared
import SwiftData
import SwiftUI

struct TakeoffView: View {
  @Environment(\.modelContext)
  private var modelContext

  @State private var performance: TakeoffPerformanceViewModel?
  @State private var weather: WeatherViewModel?

  var body: some View {
    NavigationStack {
      if performance != nil && weather != nil {
        Form {
          TakeoffPerformanceView()
          TakeoffResultsView()
          TakeoffReportsView()
        }.navigationTitle("Takeoff")
      } else {
        ProgressView()
          .controlSize(.extraLarge)
          .navigationTitle("Takeoff")
      }
    }
    .environment(performance)
    .environment(weather)
    .environment(\.operation, .takeoff)
    .withErrorSheet(state: performance)
    .onAppear {
      if performance == nil {
        performance = .init(container: modelContext.container)
      }
      if weather == nil {
        weather = .init(
          operation: .takeoff,
          container: modelContext.container,
          loader: UITestingHelper.weatherLoader
        )
      }
    }
    .onChange(of: weather?.conditions) {
      performance?.conditions = weather?.conditions ?? .init()
    }
  }
}

#Preview {
  PreviewView(insert: .KOAK) { preview in
    let runway = try preview.load(airportID: "OAK", runway: "28R")!
    preview.setTakeoff(runway: runway)

    return TakeoffView()
  }
}
