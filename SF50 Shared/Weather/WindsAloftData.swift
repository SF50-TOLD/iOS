public import Foundation
import MeasurementKit
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
public struct WindsAloftData: Sendable, Hashable {

  /// Wind and temperature entries at various altitudes.
  public let entries: [Entry]

  /// Creates winds aloft data from a SwiftMETAR station.
  ///
  /// - Parameter station: The parsed station data from SwiftMETAR.
  init(from station: WindsAloft.Station) {
    self.entries = station.entries.map { Entry(altitude: $0.altitude, entry: $0.data) }
  }

  /// Creates winds aloft data with explicit values (for testing and interpolation).
  ///
  /// - Parameter entries: Wind/temperature entries at various altitudes
  public init(entries: [Entry]) {
    self.entries = entries
  }

  /// Whether an altitude falls within the levels this data actually reports.
  ///
  /// The bulletins omit levels within 1,500 feet of a station's elevation, so a station on high
  /// terrain may report nothing below 9,000 or 12,000 feet. ``entry(at:)`` clamps to the nearest
  /// reported level outside that range, which is right when sampling this station's own column and
  /// wrong when combining it with others.
  ///
  /// - Parameter altitude: The altitude to test.
  /// - Returns: Whether the altitude is bracketed by reported levels.
  public func covers(altitude: Measurement<UnitLength>) -> Bool {
    guard let lowest = entries.map(\.altitude).min(),
      let highest = entries.map(\.altitude).max()
    else { return false }
    return altitude >= lowest && altitude <= highest
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
    let fraction = (altitude - lower.altitude) / (upper.altitude - lower.altitude)

    return Entry.interpolate(from: lower, to: upper, fraction: fraction, altitude: altitude)
  }

  /// A single altitude entry containing wind and temperature data.
  public struct Entry: Sendable, Hashable {
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
      switch entry {
        case .lightAndVariable:
          self.windDirection = nil
          self.windSpeed = .init(value: 0, unit: .knots)
        case .wind:
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
      .init(
        altitude: altitude,
        windDirection: interpolateDirection(
          from.windDirection,
          to.windDirection,
          fraction: fraction
        ),
        windSpeed: from.windSpeed + (to.windSpeed - from.windSpeed) * fraction,
        temperature: interpolateTemperature(from.temperature, to.temperature, fraction: fraction)
      )
    }

    /// Interpolates between two wind directions using shortest path around the compass.
    private static func interpolateDirection(
      _ from: Measurement<UnitAngle>?,
      _ to: Measurement<UnitAngle>?,
      fraction: Double
    ) -> Measurement<UnitAngle>? {
      guard let from, let to else { return from ?? to }

      let fromDeg = from.converted(to: .degrees).value,
        toDeg = to.converted(to: .degrees).value
      var diff = toDeg - fromDeg
      if diff > 180 { diff -= 360 } else if diff < -180 { diff += 360 }
      var result = fromDeg + diff * fraction
      if result < 0 { result += 360 }
      if result >= 360 { result -= 360 }
      return .init(value: result, unit: .degrees)
    }

    /// Interpolates between two optional temperatures, falling back to whichever side reports one.
    private static func interpolateTemperature(
      _ from: Measurement<UnitTemperature>?,
      _ to: Measurement<UnitTemperature>?,
      fraction: Double
    ) -> Measurement<UnitTemperature>? {
      guard let from, let to else { return from ?? to }
      return from + (to - from) * fraction
    }
  }
}
