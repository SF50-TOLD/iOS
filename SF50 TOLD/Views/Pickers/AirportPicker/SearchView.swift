import Defaults
import SF50_Shared
import SwiftData
import SwiftUI

struct SearchView: View {
  var onSelect: (Airport) -> Void

  @State private var searchText = ""
  @State private var viewModel: SearchViewModel?

  @Environment(\.modelContext)
  private var modelContext

  var body: some View {
    // The search field attaches to the navigation stack that presented the
    // picker; a nested stack here would outlive the pop and strand the field
    // onscreen. It also has to hang off a view that is always rendered, or the
    // field and this view's lifecycle events disappear along with the results.
    SearchResults(airports: viewModel?.sortedAirports ?? [], onSelect: onSelect)
      .searchable(text: $searchText)
      .onChange(of: searchText) { _, searchText in viewModel?.searchText = searchText }
      .onAppear {
        if viewModel == nil {
          viewModel = SearchViewModel(container: modelContext.container)
        }
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
      SearchView { _ in }
    }
  }
}
