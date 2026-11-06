import Foundation

extension WeatherLoader {
  /// Gets Open-Meteo's winds aloft for a key, or `nil` if its forecast doesn't reach the key's time.
  ///
  /// A forecast that couldn't be downloaded is reported as an error, so that a pilot can tell a
  /// failed download, which is worth a retry, from a time the model doesn't forecast.
  func windsAloftForecast(for key: Key) async -> Loadable<WindsAloftForecast?> {
    do {
      return .value(try await OpenMeteoService.shared.windsAloft(for: key))
    } catch {
      Self.recordLoadFailure(error, dataType: "openMeteo", airport: key.id)
      return .error(error)
    }
  }
}
