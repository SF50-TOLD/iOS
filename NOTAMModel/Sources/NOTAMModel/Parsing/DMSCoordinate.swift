internal import Foundation

/// A latitude or longitude written as degrees, minutes and seconds (`403906N`, `0734931.5W`), the way
/// NOTAMs state positions, converted to the decimal degrees the schema records.
enum DMSCoordinate {
  private static let secondsPerMinute = 60.0, minutesPerDegree = 60.0
  private static let decimalPlaces = 6.0

  private static var latitude: Regex<(Substring, Substring, Substring, Substring, Substring)> {
    /(\d{2})(\d{2})(\d{2}(?:\.\d+)?)([NS])/
  }
  private static var longitude: Regex<(Substring, Substring, Substring, Substring, Substring)> {
    /(\d{3})(\d{2})(\d{2}(?:\.\d+)?)([EW])/
  }

  /// Decimal degrees for a written latitude, north positive, to 6 places; `nil` if it isn't one.
  static func latitude(_ written: some StringProtocol) -> Double? {
    (try? latitude.wholeMatch(in: String(written))).flatMap(decimalDegrees)
  }

  /// Decimal degrees for a written longitude, east positive, to 6 places; `nil` if it isn't one.
  static func longitude(_ written: some StringProtocol) -> Double? {
    (try? longitude.wholeMatch(in: String(written))).flatMap(decimalDegrees)
  }

  private static func decimalDegrees(
    _ match: Regex<(Substring, Substring, Substring, Substring, Substring)>.Match
  ) -> Double? {
    guard let degrees = Double(match.1), let minutes = Double(match.2),
      let seconds = Double(match.3),
      minutes < minutesPerDegree, seconds < secondsPerMinute
    else { return nil }
    let magnitude = degrees + (minutes + seconds / secondsPerMinute) / minutesPerDegree
    let scale = pow(10, decimalPlaces)
    let rounded = (magnitude * scale).rounded() / scale
    return match.4 == "S" || match.4 == "W" ? -rounded : rounded
  }
}
