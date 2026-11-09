import SF50_Shared
import SwiftUI

// MARK: - Environment

private struct AircraftKey: EnvironmentKey {
  static let defaultValue = Aircraft.sf50(.g2(updatedThrustSchedule: false))
}

extension EnvironmentValues {
  /// The current aircraft for the view hierarchy.
  ///
  /// This provides the effective aircraft, accounting for legacy
  /// `updatedThrustSchedule` settings when `aircraft` is not explicitly set.
  var aircraft: Aircraft {
    get { self[AircraftKey.self] }
    set { self[AircraftKey.self] = newValue }
  }
}
