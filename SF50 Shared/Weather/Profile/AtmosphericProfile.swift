public import CoreLocation
public import Foundation
import MeasurementKit

/// The atmosphere in a vertical column above one point, as a forecast model reports it.
///
/// ``AtmosphericProfile`` is what the weather layers of a climb profile are drawn from: the
/// temperature the aircraft climbs through, the cloud it climbs into, and the humidity that decides
/// whether the cold part of that climb is icing.
///
/// Wind is deliberately absent. The winds a climb was flown on come from ``WindsAloftForecast`` by
/// way of ``ClimbProfile``, and sampling a second source for the same quantity would let the drawn
/// wind disagree with the flown one.
///
/// ## Usage
///
/// ```swift
/// let profiles = try await OpenMeteoService.shared.profiles(at: [coordinate], for: .now)
/// if let profile = profiles.first ?? nil,
///    let level = profile.level(at: .init(value: 5000, unit: .feet)) {
///     print("\(level.temperature?.formatted() ?? "—") at 5,000 ft")
/// }
/// ```
public struct AtmosphericProfile: Sendable {

  /// The latitude of the column, in degrees.
  ///
  /// Stored as a pair of doubles rather than a `CLLocationCoordinate2D` so the profile can be
  /// compared and hashed; the coordinate type is neither `Equatable` nor `Hashable`.
  public let latitude: Double

  /// The longitude of the column, in degrees.
  public let longitude: Double

  /// The period this column describes.
  public let validTime: DateInterval

  /// The reported levels, ordered from the lowest altitude upwards.
  public let levels: [Level]

  /// The geographic point this column stands above.
  public var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }

  /// Creates a profile from levels reported above a point.
  ///
  /// - Parameters:
  ///   - coordinate: The point the column stands above.
  ///   - validTime: The period the column describes.
  ///   - levels: The reported levels, in any order.
  public init(coordinate: CLLocationCoordinate2D, validTime: DateInterval, levels: [Level]) {
    latitude = coordinate.latitude
    longitude = coordinate.longitude
    self.validTime = validTime
    self.levels = levels.sorted { $0.altitude < $1.altitude }
  }

  /// The conditions at an altitude, interpolated between the levels bracketing it.
  ///
  /// Altitudes outside the reported range take the nearest level's values rather than nothing. A
  /// model's lowest pressure level stands some way above the ground, and a field that faded out
  /// below it would read as an absence of weather rather than the edge of the report — the same
  /// reasoning that has ``ClimbProfile`` carry its lowest wind down to the surface.
  ///
  /// - Parameter altitude: The altitude to read.
  /// - Returns: The conditions there, or `nil` if the column has no levels at all.
  public func level(at altitude: Measurement<UnitLength>) -> Level? {
    guard let lowest = levels.first, let highest = levels.last else { return nil }
    if altitude <= lowest.altitude { return lowest.moved(to: altitude) }
    if altitude >= highest.altitude { return highest.moved(to: altitude) }

    guard let upperIndex = levels.firstIndex(where: { $0.altitude >= altitude }),
      upperIndex > 0
    else { return lowest.moved(to: altitude) }

    let lower = levels[upperIndex - 1],
      upper = levels[upperIndex]
    let depth = upper.altitude - lower.altitude
    guard depth.value > 0 else { return lower.moved(to: altitude) }

    return .interpolate(
      from: lower,
      to: upper,
      fraction: (altitude - lower.altitude) / depth,
      altitude: altitude
    )
  }

  /// The conditions at one pressure level of a column.
  public struct Level: Sendable, Hashable {

    /// The altitude these conditions were reported at.
    public let altitude: Measurement<UnitLength>

    /// The temperature, or `nil` where the model doesn't report one.
    public let temperature: Measurement<UnitTemperature>?

    /// The relative humidity as a fraction from zero to one, or `nil` where unreported.
    public let relativeHumidity: Double?

    /// The fraction of the sky covered by cloud, from zero to one, or `nil` where unreported.
    public let cloudCover: Double?

    /// Creates a level from its reported values.
    ///
    /// - Parameters:
    ///   - altitude: The altitude the values were reported at.
    ///   - temperature: The temperature.
    ///   - relativeHumidity: The relative humidity, as a fraction from zero to one.
    ///   - cloudCover: The sky covered by cloud, as a fraction from zero to one.
    public init(
      altitude: Measurement<UnitLength>,
      temperature: Measurement<UnitTemperature>?,
      relativeHumidity: Double?,
      cloudCover: Double?
    ) {
      self.altitude = altitude
      self.temperature = temperature
      self.relativeHumidity = relativeHumidity
      self.cloudCover = cloudCover
    }

    /// Interpolates between two levels.
    ///
    /// - Parameters:
    ///   - from: The lower level.
    ///   - to: The upper level.
    ///   - fraction: How far between them, where zero is `from` and one is `to`.
    ///   - altitude: The altitude to report the result at.
    /// - Returns: The interpolated level.
    static func interpolate(
      from: Self,
      to: Self,
      fraction: Double,
      altitude: Measurement<UnitLength>
    ) -> Self {
      .init(
        altitude: altitude,
        temperature: interpolate(from.temperature, to.temperature, fraction: fraction),
        relativeHumidity: interpolate(
          from.relativeHumidity,
          to.relativeHumidity,
          fraction: fraction
        ),
        cloudCover: interpolate(from.cloudCover, to.cloudCover, fraction: fraction)
      )
    }

    /// Interpolates between two optional values, falling back to whichever side reports one.
    private static func interpolate(_ from: Double?, _ to: Double?, fraction: Double) -> Double? {
      guard let from, let to else { return from ?? to }
      return from + (to - from) * fraction
    }

    /// Interpolates between two optional temperatures, falling back to whichever side reports one.
    private static func interpolate(
      _ from: Measurement<UnitTemperature>?,
      _ to: Measurement<UnitTemperature>?,
      fraction: Double
    ) -> Measurement<UnitTemperature>? {
      guard let from, let to else { return from ?? to }
      return from + (to - from) * fraction
    }

    /// Returns these values restated at another altitude, for a clamped read outside the range.
    func moved(to altitude: Measurement<UnitLength>) -> Self {
      .init(
        altitude: altitude,
        temperature: temperature,
        relativeHumidity: relativeHumidity,
        cloudCover: cloudCover
      )
    }
  }
}
