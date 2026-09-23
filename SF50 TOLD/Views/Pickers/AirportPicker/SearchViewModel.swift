import Foundation
import SF50_Shared
import Sentry
import SwiftData

@Observable
@MainActor
final class SearchViewModel: WithIdentifiableError {
  private static let debounceInterval = Duration.milliseconds(250)
  private static let minimumSearchLength = 3
  private static let matchesNothing = #Predicate<Airport> { _ in false }

  // Inputs
  var searchText = "" {
    didSet { debouncedSearch() }
  }

  var error: (any Error)?

  private let matches: ResultsObserver<Airport, Never>?
  private var appliedSearchText = ""
  private var searchTask: Task<Void, Never>?

  // Outputs
  var sortedAirports: [Airport] {
    guard let matches, !appliedSearchText.isEmpty else { return [] }
    return Airport.ranked(Array(matches.results), matching: appliedSearchText)
  }

  init(modelContext: ModelContext) {
    do {
      matches = try ResultsObserver(filterBy: Self.matchesNothing, modelContext: modelContext)
    } catch {
      SentrySDK.capture(error: error)
      matches = nil
      self.error = error
    }
  }

  private func debouncedSearch() {
    searchTask?.cancel()
    searchTask = Task {
      try? await Task.sleep(for: Self.debounceInterval)
      if !Task.isCancelled { applySearchText() }
    }
  }

  private func applySearchText() {
    appliedSearchText = searchText.count >= Self.minimumSearchLength ? searchText : ""
    matches?.filterBy =
      appliedSearchText.isEmpty
      ? Self.matchesNothing : Airport.searchPredicate(matching: appliedSearchText)
  }
}
