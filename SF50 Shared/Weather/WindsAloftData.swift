public import Foundation

/// Winds aloft over a single point: wind and temperature at each of a forecast's levels.
public struct WindsAloftData: Sendable, Hashable {

  /// Wind and temperature entries at various altitudes.
  public let entries: [Entry]

  /// Creates winds aloft data from its levels.
  ///
  /// - Parameter entries: Wind/temperature entries at various altitudes
  public init(entries: [Entry]) {
    self.entries = entries
  }

  /// A single altitude entry containing wind and temperature data.
  public struct Entry: Sendable, Hashable {
    /// The altitude for this entry.
    public let altitude: Measurement<UnitLength>

    /// The wind direction in degrees true, or `nil` if not reported.
    public let windDirection: Measurement<UnitAngle>?

    /// The wind speed.
    public let windSpeed: Measurement<UnitSpeed>

    /// The temperature at this altitude, or `nil` if not reported.
    public let temperature: Measurement<UnitTemperature>?

    /// Creates an entry from explicit values.
    public init(
      altitude: Measurement<UnitLength>,
      windDirection: Measurement<UnitAngle>?,
      windSpeed: Measurement<UnitSpeed>,
      temperature: Measurement<UnitTemperature>?
    ) {
      self.altitude = altitude
      self.windDirection = windDirection
      self.windSpeed = windSpeed
      self.temperature = temperature
    }
  }
}
