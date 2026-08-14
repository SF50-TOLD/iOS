import Foundation

/// Winds aloft for one station, together with the forecast period it was taken from.
///
/// The NWS publishes three winds aloft bulletins per issuance — 6-, 12-, and 24-hour forecasts —
/// each with the period it is meant to be used for. ``WindsAloftForecast`` pairs the station data
/// served for a requested time with that provenance, so a climb profile can show which forecast it
/// was built from.
///
/// ## Usage
///
/// ```swift
/// for await forecast in await loader.streamWindsAloft(for: key) {
///     if let forecast = forecast.value ?? nil {
///         print("Valid at \(forecast.validAt): \(forecast.data.entries.count) levels")
///     }
/// }
/// ```
public struct WindsAloftForecast: Sendable, Hashable {

  /// The time the forecast is valid at.
  public let validAt: Date

  /// The period the NWS publishes this forecast for.
  public let usePeriod: DateInterval

  /// Where the wind and temperature data came from.
  public let source: Source

  /// The wind and temperature data.
  public let data: WindsAloftData

  /// Whether the forecast was interpolated rather than reported for the airport.
  public var isInterpolated: Bool { source == .interpolated }

  /// Creates a forecast from wind data and the period it came from.
  ///
  /// - Parameters:
  ///   - validAt: The time the forecast is valid at.
  ///   - usePeriod: The period the forecast is published for.
  ///   - source: Where the data came from.
  ///   - data: The wind and temperature data.
  public init(
    validAt: Date,
    usePeriod: DateInterval,
    source: Source,
    data: WindsAloftData
  ) {
    self.validAt = validAt
    self.usePeriod = usePeriod
    self.source = source
    self.data = data
  }

  /// Where a forecast’s winds came from.
  ///
  /// The NWS publishes forecasts for 233 locations, so most airports have no forecast of their own
  /// and are flown on one interpolated from the stations around them. Which of the two a profile
  /// was built from is worth telling the pilot.
  public enum Source: Sendable, Hashable {

    /// Reported at a station serving the airport.
    case station(String)

    /// Interpolated between the reporting stations nearest the airport.
    case interpolated
  }
}
