import Foundation
import SwiftMETAR

/// Winds aloft data for a single station.
///
/// ``WindsAloftData`` wraps SwiftMETAR's `WindsAloft.Station` providing convenience
/// accessors for wind and temperature data at various altitudes.
///
/// ## Usage
///
/// ```swift
/// let windsAloft = await loader.streamWindsAloft(for: key)
/// for await data in windsAloft {
///     if let entry = data.value?.entry(at: .init(value: 9000, unit: .feet)) {
///         print("Wind at 9000ft: \(entry.windDirection) at \(entry.windSpeed)")
///     }
/// }
/// ```
public struct WindsAloftData: Sendable, Equatable {

  /// The station identifier (e.g., "SFO", "OAK").
  public let stationID: String

  /// Wind and temperature entries at various altitudes.
  public let entries: [Entry]

  /// Creates winds aloft data from a SwiftMETAR station.
  ///
  /// - Parameter station: The parsed station data from SwiftMETAR.
  init(from station: WindsAloft.Station) {
    self.stationID = station.id
    self.entries = station.entries.map { Entry(altitude: $0.altitude, entry: $0.data) }
  }

  /// Creates winds aloft data with explicit values (for testing and interpolation).
  ///
  /// - Parameters:
  ///   - stationID: Station identifier
  ///   - entries: Wind/temperature entries at various altitudes
  public init(stationID: String, entries: [Entry]) {
    self.stationID = stationID
    self.entries = entries
  }

  /// Returns interpolated wind/temperature data for the specified altitude.
  ///
  /// Performs linear interpolation between bounding altitude levels.
  /// Light & variable winds are treated as calm (0 knots).
  /// If altitude is outside data range, returns the nearest boundary value.
  ///
  /// - Parameter altitude: The target altitude.
  /// - Returns: Interpolated entry, or `nil` if no data available.
  public func entry(at altitude: Measurement<UnitLength>) -> Entry? {
    guard !entries.isEmpty else { return nil }

    let sorted = entries.sorted { $0.altitude < $1.altitude }

    // Find bounding entries
    guard let lowerIndex = sorted.lastIndex(where: { $0.altitude <= altitude }) else {
      // Below all entries - return lowest
      return sorted.first
    }

    let lower = sorted[lowerIndex]

    // Check if we're exactly at this level or at/above the highest
    if lowerIndex == sorted.count - 1 || lower.altitude == altitude {
      return lower
    }

    let upper = sorted[lowerIndex + 1]

    // Calculate interpolation fraction
    let targetFeet = altitude.converted(to: .feet).value
    let lowerFeet = lower.altitude.converted(to: .feet).value
    let upperFeet = upper.altitude.converted(to: .feet).value
    let fraction = (targetFeet - lowerFeet) / (upperFeet - lowerFeet)

    return Entry.interpolate(from: lower, to: upper, fraction: fraction, altitude: altitude)
  }

  /// A single altitude entry containing wind and temperature data.
  public struct Entry: Sendable, Equatable {
    /// The altitude for this entry.
    public let altitude: Measurement<UnitLength>

    /// The wind direction in degrees true, or `nil` if light and variable.
    public let windDirection: Measurement<UnitAngle>?

    /// The wind speed. Light and variable winds are represented as 0 knots.
    public let windSpeed: Measurement<UnitSpeed>

    /// The temperature at this altitude, or `nil` if not reported.
    public let temperature: Measurement<UnitTemperature>?

    init(altitude: UInt, entry: WindsAloftEntry) {
      self.altitude = .init(value: Double(altitude), unit: .feet)
      if entry == .lightAndVariable {
        self.windDirection = nil
        self.windSpeed = .init(value: 0, unit: .knots)
      } else {
        self.windDirection = entry.directionMeasurement
        self.windSpeed = entry.speedMeasurement ?? .init(value: 0, unit: .knots)
      }
      self.temperature = entry.temperatureMeasurement
    }

    /// Creates an entry with explicit values (for interpolation results).
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

    /// Interpolates between two entries.
    ///
    /// - Parameters:
    ///   - from: Lower altitude entry
    ///   - to: Upper altitude entry
    ///   - fraction: Interpolation fraction (0.0 = from, 1.0 = to)
    ///   - altitude: Target altitude for the result
    /// - Returns: Interpolated entry
    static func interpolate(
      from: Self,
      to: Self,
      fraction: Double,
      altitude: Measurement<UnitLength>
    ) -> Self {
      // Interpolate wind speed
      let fromSpeed = from.windSpeed.converted(to: .knots).value
      let toSpeed = to.windSpeed.converted(to: .knots).value
      let interpolatedSpeed = fromSpeed + (toSpeed - fromSpeed) * fraction
      let windSpeed: Measurement<UnitSpeed> = .init(value: interpolatedSpeed, unit: .knots)

      // Interpolate wind direction (circular interpolation)
      let windDirection = interpolateDirection(
        from.windDirection?.converted(to: .degrees).value,
        to.windDirection?.converted(to: .degrees).value,
        fraction: fraction
      ).map { Measurement<UnitAngle>(value: $0, unit: .degrees) }

      // Interpolate temperature
      let temperature: Measurement<UnitTemperature>?
      if let fromTemp = from.temperature?.converted(to: .celsius).value,
        let toTemp = to.temperature?.converted(to: .celsius).value
      {
        let interpolatedTemp = fromTemp + (toTemp - fromTemp) * fraction
        temperature = .init(value: interpolatedTemp, unit: .celsius)
      } else {
        temperature = from.temperature ?? to.temperature
      }

      return Self(
        altitude: altitude,
        windDirection: windDirection,
        windSpeed: windSpeed,
        temperature: temperature
      )
    }

    /// Interpolates between two wind directions using shortest path around the compass.
    private static func interpolateDirection(_ from: Double?, _ to: Double?, fraction: Double)
      -> Double?
    {
      guard let from, let to else { return from ?? to }
      var diff = to - from
      if diff > 180 { diff -= 360 } else if diff < -180 { diff += 360 }
      var result = from + diff * fraction
      if result < 0 { result += 360 }
      if result >= 360 { result -= 360 }
      return result
    }
  }
}
