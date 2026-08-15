import Foundation

extension WindsAloftForecast {
  /// Creates a winds aloft forecast from an Open-Meteo forecast's pressure levels.
  ///
  /// Each level's altitude is its geopotential height rather than a standard-atmosphere conversion
  /// of its pressure, so the column stands where the model actually puts it. Levels at or below the
  /// model's own terrain are dropped: the model extrapolates them rather than forecasting them, and
  /// a climb profile clamps to its lowest level anyway, so the ground is still covered.
  ///
  /// Unlike an NWS bulletin, which is published for a period hours wide, an Open-Meteo hour applies
  /// to that hour alone.
  ///
  /// - Parameters:
  ///   - openMeteo: The forecast to read.
  ///   - time: The time winds aloft are needed for.
  init?(openMeteo: OpenMeteoResponse, at time: Date) {
    guard let hour = openMeteo.hour(covering: time) else { return nil }

    let entries = OpenMeteoVariable.pressureLevelsHPa
      .compactMap { WindsAloftData.Entry(hour: hour, levelHPa: $0) }
      .filter { $0.altitude > openMeteo.elevation }
      .sorted { $0.altitude < $1.altitude }
    guard !entries.isEmpty else { return nil }

    self.init(
      validAt: hour.interval.start,
      usePeriod: hour.interval,
      source: .openMeteo,
      data: .init(entries: entries)
    )
  }
}

extension WindsAloftData.Entry {
  /// Creates an entry from one of a forecast hour's pressure levels.
  ///
  /// - Parameters:
  ///   - hour: The forecast hour to read.
  ///   - levelHPa: The pressure level, in hectopascals.
  fileprivate init?(hour: OpenMeteoResponse.Hour, levelHPa: Int) {
    guard let heightM = hour.value(of: OpenMeteoVariable.height(atHPa: levelHPa)),
      let windSpeedKts = hour.value(of: OpenMeteoVariable.windSpeed(atHPa: levelHPa))
    else { return nil }

    self.init(
      altitude: Measurement<UnitLength>(value: heightM, unit: .meters).converted(to: .feet),
      windDirection: hour.value(of: OpenMeteoVariable.windDirection(atHPa: levelHPa))
        .map { .init(value: $0, unit: .degrees) },
      windSpeed: .init(value: windSpeedKts, unit: .knots),
      temperature: hour.value(of: OpenMeteoVariable.temperature(atHPa: levelHPa))
        .map { .init(value: $0, unit: .celsius) }
    )
  }
}
