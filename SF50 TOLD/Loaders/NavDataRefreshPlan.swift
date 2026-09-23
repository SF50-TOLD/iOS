import Foundation

/// When the background nav-data refresh should run, decided from the dataset installed.
enum NavDataRefreshPlan: Equatable {
  /// Nothing is installed, so there is nothing to refresh: the first load is the pilot's to start.
  case none

  /// The installed dataset is out of date already, so refresh as soon as iOS allows.
  case now

  /// The installed dataset is current, so refresh once its cycle expires.
  case at(Date)

  /// Plans the refresh for a dataset in `state`.
  ///
  /// - Parameter state: The installed dataset's state.
  init(_ state: NavDataStateHelper.State) {
    if state.noData {
      self = .none
    } else if !state.needsLoad, let expires = state.nasrCycleExpires {
      self = .at(expires)
    } else {
      self = .now
    }
  }
}
