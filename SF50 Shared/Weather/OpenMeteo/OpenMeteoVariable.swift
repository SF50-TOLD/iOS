import Foundation

/// The names Open-Meteo reports each requested weather variable under.
///
/// Requesting a variable and reading it back are the same string, so both sides are spelled once
/// here. See the [forecast API reference](https://open-meteo.com/en/docs).
enum OpenMeteoVariable {

  /// The pressure levels winds aloft are requested at, in hectopascals.
  ///
  /// 200 hPa stands about 38,600 feet up, comfortably above the SF50's service ceiling, and ten
  /// levels keep the response small enough to fetch on a cellular connection.
  static let pressureLevelsHPa = [1000, 925, 850, 700, 600, 500, 400, 300, 250, 200]

  static let time = "time",
    temperature = "temperature_2m",
    dewpoint = "dew_point_2m",
    seaLevelPressure = "pressure_msl",
    windSpeed = "wind_speed_10m",
    windDirection = "wind_direction_10m"

  /// Every variable to request, as the API's comma-separated `hourly` parameter expects them.
  static var requested: [String] {
    [temperature, dewpoint, seaLevelPressure, windSpeed, windDirection]
      + pressureLevelsHPa.flatMap {
        [temperature(atHPa: $0), windSpeed(atHPa: $0), windDirection(atHPa: $0), height(atHPa: $0)]
      }
  }

  static func temperature(atHPa levelHPa: Int) -> String { "temperature_\(levelHPa)hPa" }

  static func windSpeed(atHPa levelHPa: Int) -> String { "wind_speed_\(levelHPa)hPa" }

  static func windDirection(atHPa levelHPa: Int) -> String { "wind_direction_\(levelHPa)hPa" }

  /// The geopotential height of a pressure level, which is the altitude its winds blow at.
  static func height(atHPa levelHPa: Int) -> String { "geopotential_height_\(levelHPa)hPa" }
}
