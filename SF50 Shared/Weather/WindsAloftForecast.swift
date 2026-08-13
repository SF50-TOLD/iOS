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

  /// The station’s wind and temperature data.
  public let data: WindsAloftData

  /// Creates a forecast from station data and the period it came from.
  ///
  /// - Parameters:
  ///   - validAt: The time the forecast is valid at.
  ///   - usePeriod: The period the forecast is published for.
  ///   - data: The station’s wind and temperature data.
  public init(validAt: Date, usePeriod: DateInterval, data: WindsAloftData) {
    self.validAt = validAt
    self.usePeriod = usePeriod
    self.data = data
  }
}
