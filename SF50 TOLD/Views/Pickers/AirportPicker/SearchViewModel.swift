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
  var error: (any Error)?

  private let container: ModelContainer
  private var searchTask: Task<Void, Never>?

  init(container: ModelContainer) {
    self.container = container
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

    Task { [weak self] in
      guard let self else { return }
      do {
        let topResults = try await searchAirports(matching: searchTextCopy)
        // Only update if search text hasn't changed
        guard searchTextCopy == searchText else { return }
        sortedAirports = topResults
        isLoading = false
        error = nil
      } catch {
        SentrySDK.capture(error: error)
        sortedAirports = []
        isLoading = false
        self.error = error
      }
    }
  }

  /// Fetches and relevance-ranks airports matching the query on a background
  /// context.
  @concurrent
  private func searchAirports(matching searchText: String) async throws
    -> sending [Airport]
  {
    let context = ModelContext(container)
    let descriptor = FetchDescriptor(predicate: Airport.searchPredicate(matching: searchText))
    let results = try context.fetch(descriptor)

    // Pre-compute scores off the main actor to avoid redundant computation in
    // the sort comparator (O(n) vs O(n log n) calls)
    let scored: [(airport: Airport, relevance: Int, similarity: Double)] = results.map {
      airport in
      let relevance = Airport.relevanceScore(for: airport, searchText: searchText)
      let nameSim = Self.nameSimilarity(airport.name, to: searchText)
      let citySim = Self.citySimilarity(airport.city, to: searchText)
      return (airport: airport, relevance: relevance, similarity: max(nameSim, citySim))
    }

    let sorted = scored.sorted { a, b in
      if a.relevance != b.relevance { return a.relevance > b.relevance }
      if a.similarity != b.similarity { return a.similarity > b.similarity }
      return a.airport.name.localizedStandardCompare(b.airport.name) == .orderedAscending
    }

    return Array(sorted.prefix(Airport.searchResultLimit).map(\.airport))
  }
}
