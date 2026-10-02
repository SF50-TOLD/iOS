import Defaults
import SF50_Shared
import SwiftUI

/// A view that provides the aircraft type to its children via the environment.
///
/// This view observes `aircraftTypeSetting` and `updatedThrustSchedule` from Defaults,
/// constructing the full `AircraftType` and injecting it into the environment. This
/// allows child views to simply use `@Environment(\.aircraftType)` without needing
/// to access Defaults directly.
///
/// ## Usage
/// ```swift
/// AircraftTypeProvider {
///   // Child views can use @Environment(\.aircraftType)
///   MyView()
/// }
/// ```
struct AircraftTypeProvider<Content: View>: View {
  @Default(.aircraftTypeSetting)
  private var aircraftTypeSetting

  @Default(.updatedThrustSchedule)
  private var updatedThrustSchedule

  @ViewBuilder var content: () -> Content

  private var aircraftType: AircraftType {
    .init(setting: aircraftTypeSetting, updatedThrustSchedule: updatedThrustSchedule)
  }

  var body: some View {
    content()
      .environment(\.aircraftType, aircraftType)
  }
}
