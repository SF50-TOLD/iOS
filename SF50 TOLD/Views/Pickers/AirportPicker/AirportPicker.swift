import Defaults
import SF50_Shared
import SwiftUI

private enum AirportPickerTabs {
  case favorites
  case recents
  case nearest
}

struct AirportPicker: View {
  var onSelect: (Airport) -> Void

  @State private var tabIndex: AirportPickerTabs = .favorites
  @State private var searchText = ""

  @Environment(\.presentationMode)
  private var mode

  @Default(.recentAirports)
  private var recentAirports

  var body: some View {
    // The search field attaches to the navigation stack that presented the
    // picker; a nested stack here would outlive the pop and strand the field
    // onscreen.
    Group {
      if searchText.isEmpty {
        VStack(alignment: .leading) {
          Picker("Tab", selection: $tabIndex) {
            Text("Favorites").tag(AirportPickerTabs.favorites)
            Text("Recents").tag(AirportPickerTabs.recents)
            Text("Nearest").tag(AirportPickerTabs.nearest)
          }
          .pickerStyle(SegmentedPickerStyle())
          .padding(.horizontal)
          .accessibilityIdentifier("airportListPicker")

          switch tabIndex {
            case .favorites: FavoritesView(onSelect: selectAndDismiss)
            case .recents: RecentsView(onSelect: selectAndDismiss)
            case .nearest: NearestView(onSelect: selectAndDismiss)
          }
        }
      } else {
        SearchView(searchText: searchText, onSelect: selectAndDismiss)
      }
    }
    .searchable(text: $searchText)
  }

  private func selectAndDismiss(airport: Airport) {
    recentAirports.appendRemovingDuplicates(of: airport.recordID)
    if recentAirports.count > 10 {
      recentAirports.removeFirst(recentAirports.count - 10)
    }

    onSelect(airport)
    mode.wrappedValue.dismiss()
  }
}

#Preview {
  PreviewView(insert: .KOAK, .K1C9, .KSQL) { preview in
    preview.setUpToDate()
    Defaults[.favoriteAirports] = ["OAK"]
    Defaults[.recentAirports] = ["SQL"]

    return NavigationStack {
      AirportPicker { _ in }
        .environment(\.locationStreamer, MockLocationStreamer())
    }
  }
}
