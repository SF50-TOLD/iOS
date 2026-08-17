import CoreLocation
import Foundation

extension AtmosphericProfile {
  /// Creates a profile from an Open-Meteo forecast's pressure levels.
  ///
  /// Each level's altitude is its geopotential height rather than a standard-atmosphere conversion
  /// of its pressure, so the column stands where the model actually puts it. Levels at or below the
  /// model's own terrain are dropped: the model extrapolates them rather than forecasting them, and
  /// ``AtmosphericProfile/level(at:)`` carries its lowest level down anyway, so the ground is still
  /// covered.
  ///
  /// - Parameters:
  ///   - openMeteo: The forecast to read.
  ///   - coordinate: The point the forecast was requested for.
  ///   - time: The time the profile is needed for.
  init?(openMeteo: OpenMeteoResponse, at coordinate: CLLocationCoordinate2D, for time: Date) {
    guard let hour = openMeteo.hour(covering: time) else { return nil }

    let levels = OpenMeteoVariable.pressureLevelsHPa
      .compactMap { Level(hour: hour, levelHPa: $0) }
      .filter { $0.altitude > openMeteo.elevation }
    guard !levels.isEmpty else { return nil }

    self.init(coordinate: coordinate, validTime: hour.interval, levels: levels)
  }
}

extension AtmosphericProfile.Level {
  /// Creates a level from one of a forecast hour's pressure levels.
  ///
  /// Open-Meteo reports cloud cover and relative humidity as percentages; both are stored here as
  /// fractions, which is what a fill opacity or a humidity threshold wants.
  ///
  /// - Parameters:
  ///   - hour: The forecast hour to read.
  ///   - levelHPa: The pressure level, in hectopascals.
  fileprivate init?(hour: OpenMeteoResponse.Hour, levelHPa: Int) {
    guard let heightM = hour.value(of: OpenMeteoVariable.height(atHPa: levelHPa)) else {
      return nil
    }

    self.init(
      altitude: Measurement<UnitLength>(value: heightM, unit: .meters).converted(to: .feet),
      temperature: hour.value(of: OpenMeteoVariable.temperature(atHPa: levelHPa))
        .map { .init(value: $0, unit: .celsius) },
      relativeHumidity: hour.value(of: OpenMeteoVariable.relativeHumidity(atHPa: levelHPa))
        .map { $0 / 100 },
      cloudCover: hour.value(of: OpenMeteoVariable.cloudCover(atHPa: levelHPa))
        .map { $0 / 100 }
    )
  }
}
