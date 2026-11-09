import Foundation

/// Aircraft flap configuration settings.
///
/// The SF50 Vision Jet has three flap positions (Up, 50%, 100%) which affect takeoff and landing
/// performance. Ice protection variants account for the performance penalty when the ice
/// protection system is active.
///
/// The app keeps its own copy of the performance models' flap setting, for the same reason as
/// `Operation`.
public enum FlapSetting: String, CaseIterable, Sendable {
  /// Flaps up (clean configuration)
  case flapsUp
  /// Flaps up with ice protection
  case flapsUpIce
  /// Flaps 50% deflection
  case flaps50
  /// Flaps 50% with ice protection
  case flaps50Ice
  /// Flaps 100% deflection
  case flaps100

  /// The same setting, as the performance models take it.
  public var performanceFlapSetting: AircraftPerformance.FlapSetting {
    switch self {
      case .flapsUp: .flapsUp
      case .flapsUpIce: .flapsUpIce
      case .flaps50: .flaps50
      case .flaps50Ice: .flaps50Ice
      case .flaps100: .flaps100
    }
  }
}
