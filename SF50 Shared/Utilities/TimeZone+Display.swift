import Defaults
public import Foundation

extension TimeZone {
  /// The time zone to display times at an airport in.
  ///
  /// Pilots choose between the airport’s local time and Zulu in Settings.
  ///
  /// - Parameter airport: The airport being displayed, if one is selected.
  /// - Returns: The airport’s time zone when local time is preferred, UTC otherwise.
  public static func display(for airport: Airport?) -> Self {
    guard Defaults[.useAirportLocalTime] else { return .gmt }
    return airport?.timeZone ?? .current
  }
}
