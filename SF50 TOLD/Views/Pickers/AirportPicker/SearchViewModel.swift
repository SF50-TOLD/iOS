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
    return Airport.ranked(try context.fetch(descriptor), matching: searchText)
  }
}
