import Defaults
import SF50_Shared
import SwiftUI

/// A view that provides the aircraft to its children via the environment.
///
/// This view observes `sf50Generation` and `updatedThrustSchedule` from Defaults,
/// constructing the full `Aircraft` and injecting it into the environment. This
/// allows child views to simply use `@Environment(\.aircraft)` without needing
/// to access Defaults directly.
///
/// ## Usage
/// ```swift
/// AircraftProvider {
///   // Child views can use @Environment(\.aircraft)
///   MyView()
/// }
/// ```
struct AircraftProvider<Content: View>: View {
  @Default(.sf50Generation)
  private var sf50Generation

  @Default(.updatedThrustSchedule)
  private var updatedThrustSchedule

  @ViewBuilder var content: () -> Content

  private var aircraft: Aircraft {
    .sf50(.init(generation: sf50Generation, updatedThrustSchedule: updatedThrustSchedule))
  }

  var body: some View {
    content()
      .environment(\.aircraft, aircraft)
  }
}
