public import Foundation

/// Winds aloft over an airport, together with the forecast hour they were taken from.
///
/// The winds come from Open-Meteo's pressure levels, and each forecast hour applies to that hour
/// alone. ``WindsAloftForecast`` pairs the levels served for a requested time with the hour they
/// belong to, so a climb profile can show which forecast it was built from.
///
/// ## Usage
///
/// ```swift
/// for await forecast in await loader.streamWindsAloft(for: key) {
///     if let forecast = forecast.value ?? nil {
///         print("Valid \(forecast.validPeriod): \(forecast.data.entries.count) levels")
///     }
/// }
/// ```
public struct WindsAloftForecast: Sendable, Hashable {

  /// The period the forecast applies to.
  public let validPeriod: DateInterval

  /// The wind and temperature data.
  public let data: WindsAloftData

  /// Creates a forecast from wind data and the period it applies to.
  ///
  /// - Parameters:
  ///   - validPeriod: The period the forecast applies to.
  ///   - data: The wind and temperature data.
  public init(validPeriod: DateInterval, data: WindsAloftData) {
    self.validPeriod = validPeriod
    self.data = data
  }
}
