import SF50_Shared
import Sentry
import SwiftData

@Observable
@MainActor
final class SearchViewModel: WithIdentifiableError {
  // Inputs
  var searchText: String = "" {
    didSet { debouncedSearch() }
  }

  // Outputs
  private(set) var sortedAirports: [Airport] = []
  private(set) var isLoading = false
  var error: Error?

  private let container: ModelContainer
  private var searchTask: Task<Void, Never>?

  init(container: ModelContainer) {
    self.container = container
  }

  nonisolated private static func relevanceScore(for airport: Airport, searchText: String) -> Int {
    if airport.locationID == searchText.uppercased() { return 3 }
    if let ICAO_ID = airport.ICAO_ID, ICAO_ID == searchText.uppercased() { return 3 }
    if airport.name.localizedStandardContains(searchText) { return 2 }
    if let city = airport.city, city.localizedStandardContains(searchText) { return 1 }
    return 0
  }

  nonisolated private static func nameSimilarity(_ name: String, to searchText: String) -> Double {
    if name.localizedStandardEquals(searchText) { return 1.0 }
    if name.localizedStandardHasPrefix(searchText) { return 0.8 }
    if name.localizedStandardContains(searchText) { return 0.6 }

    // Calculate simple similarity based on common characters
    let commonChars = Set(name.localizedLowercase).intersection(Set(searchText.localizedLowercase))
      .count
    let totalChars = max(name.count, searchText.count)
    return Double(commonChars) / Double(totalChars) * 0.4
  }

  nonisolated private static func citySimilarity(_ city: String?, to searchText: String) -> Double {
    guard let city else { return 0.0 }
    if city.localizedStandardEquals(searchText) { return 0.5 }
    if city.localizedStandardHasPrefix(searchText) { return 0.4 }
    if city.localizedStandardContains(searchText) { return 0.3 }
    return 0.0
  }

  private func debouncedSearch() {
    searchTask?.cancel()
    searchTask = Task {
      // Wait 250ms before executing the search
      try? await Task.sleep(nanoseconds: 250_000_000)
      if !Task.isCancelled { performSearch() }
    }
  }

  private func performSearch() {
    guard searchText.count > 2 else {
      sortedAirports = []
      return
    }

    isLoading = true
    let searchTextCopy = searchText

    Task { [container] in
      let context = container.mainContext
      let uppercaseText = searchTextCopy.uppercased()

      let predicate = #Predicate<Airport> { airport in
        airport.locationID == uppercaseText
          || airport.name.localizedStandardContains(searchTextCopy)
          || airport.ICAO_ID == uppercaseText
          || airport.city?.localizedStandardContains(searchTextCopy) == true
      }

      let descriptor = FetchDescriptor(predicate: predicate)

      do {
        let results = try context.fetch(descriptor)

        // Pre-compute scores on background thread to avoid redundant
        // computation in sort comparator (O(n) vs O(n log n) calls)
        let scored: [(airport: Airport, relevance: Int, similarity: Double)] = results.map {
          airport in
          let relevance = Self.relevanceScore(for: airport, searchText: searchTextCopy)
          let nameSim = Self.nameSimilarity(airport.name, to: searchTextCopy)
          let citySim = Self.citySimilarity(airport.city, to: searchTextCopy)
          return (airport: airport, relevance: relevance, similarity: max(nameSim, citySim))
        }

        let sorted = scored.sorted { a, b in
          if a.relevance != b.relevance { return a.relevance > b.relevance }
          if a.similarity != b.similarity { return a.similarity > b.similarity }
          return a.airport.name.localizedStandardCompare(b.airport.name) == .orderedAscending
        }

        let topResults = Array(sorted.prefix(10).map(\.airport))

        await MainActor.run {
          // Only update if search text hasn't changed
          if searchTextCopy == self.searchText {
            self.sortedAirports = topResults
            self.isLoading = false
            self.error = nil
          }
        }
      } catch {
        await MainActor.run {
          SentrySDK.capture(error: error)
          self.sortedAirports = []
          self.isLoading = false
          self.error = error
        }
      }
    }
  }
}
