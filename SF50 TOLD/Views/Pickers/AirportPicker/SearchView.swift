import Defaults
import SF50_Shared
import SwiftData
import SwiftUI

struct SearchView: View {
  var searchText: String
  var onSelect: (Airport) -> Void

  @State private var viewModel: SearchViewModel?

  @Environment(\.modelContext)
  private var modelContext

  var body: some View {
    SearchResults(airports: viewModel?.sortedAirports ?? [], onSelect: onSelect)
      .onChange(of: searchText, initial: true) { _, searchText in
        if viewModel == nil {
          viewModel = SearchViewModel(container: modelContext.container)
        }
        viewModel?.searchText = searchText
      }
  }
}

private struct SearchResults: View {
  var airports: [Airport]
  var onSelect: (Airport) -> Void

  var body: some View {
    if airports.isEmpty {
      List {
        Text("No results.")
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.leading)
      }
    } else {
      List(airports) { (airport: Airport) in
        AirportRow(airport: airport, showFavoriteButton: true)
          .onTapGesture {
            onSelect(airport)
          }
          .accessibility(addTraits: .isButton)
          .accessibilityIdentifier("airportRow-\(airport.displayID)")
      }
    }
  }
}

#Preview {
  PreviewView(insert: .KOAK, .K1C9, .KSQL) { preview in
    preview.setUpToDate()

    return NavigationStack {
      SearchView(searchText: "OAK") { _ in }
    }
  }
}
