import Foundation

extension Conditions {
  /// Creates conditions from an Open-Meteo forecast, or `nil` if it doesn't reach the given time.
  ///
  /// Open-Meteo answers in the units the request asked for — knots, degrees true, °C and
  /// hectopascals — so its values need no conversion. `pressure_msl` stands in for the altimeter
  /// setting, the same approximation made of WeatherKit's `pressure`.
  ///
  /// - Parameters:
  ///   - openMeteo: The forecast to read.
  ///   - time: The time conditions are needed for.
  init?(openMeteo: OpenMeteoResponse, at time: Date) {
    guard let hour = openMeteo.hour(covering: time) else { return nil }

    self.init(
      validTime: hour.interval,
      providers: .openMeteo,
      windDirection: hour.value(of: OpenMeteoVariable.windDirection)
        .map { .init(value: $0, unit: .degrees) },
      windSpeed: hour.value(of: OpenMeteoVariable.windSpeed)
        .map { .init(value: $0, unit: .knots) },
      temperature: hour.value(of: OpenMeteoVariable.temperature)
        .map { .init(value: $0, unit: .celsius) },
      dewpoint: hour.value(of: OpenMeteoVariable.dewpoint)
        .map { .init(value: $0, unit: .celsius) },
      seaLevelPressure: hour.value(of: OpenMeteoVariable.seaLevelPressure)
        .map { .init(value: $0, unit: .hectopascals) }
    )
  }
}
