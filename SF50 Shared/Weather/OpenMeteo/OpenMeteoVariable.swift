import Foundation

/// The names Open-Meteo reports each requested weather variable under.
///
/// Requesting a variable and reading it back are the same string, so both sides are spelled once
/// here. See the [forecast API reference](https://open-meteo.com/en/docs).
enum OpenMeteoVariable {

  /// The pressure levels winds aloft and atmospheric profiles are requested at, in hectopascals.
  ///
  /// 200 hPa stands about 38,600 feet up, comfortably above the SF50's service ceiling. The levels
  /// crowd together at the bottom because that is where the flying happens: a departure levelling
  /// at 2,000 feet AFE sits between 1000 and 950 hPa, so a set that jumped straight from 1000 to
  /// 925 would describe it with a single usable level.
  static let pressureLevelsHPa = [
    1000, 975, 950, 925, 900, 850, 800, 700, 600, 500, 400, 300, 250, 200
  ]

  static let time = "time",
    temperature = "temperature_2m",
    dewpoint = "dew_point_2m",
    seaLevelPressure = "pressure_msl",
    windSpeed = "wind_speed_10m",
    windDirection = "wind_direction_10m"

  /// Every variable a surface-and-winds forecast needs, as the API's `hourly` parameter expects.
  static var requested: [String] {
    [temperature, dewpoint, seaLevelPressure, windSpeed, windDirection]
      + pressureLevelsHPa.flatMap {
        [temperature(atHPa: $0), windSpeed(atHPa: $0), windDirection(atHPa: $0), height(atHPa: $0)]
      }
  }

  /// Every variable an ``AtmosphericProfile`` needs, as the API's `hourly` parameter expects.
  ///
  /// Wind is deliberately absent. A profile describes the air a layer is drawn from, and the wind
  /// drawn on that chart comes from the forecast the climb was flown on instead, so that the barbs
  /// and the climb path can never disagree.
  static var profileRequested: [String] {
    pressureLevelsHPa.flatMap {
      [
        height(atHPa: $0), temperature(atHPa: $0), cloudCover(atHPa: $0),
        relativeHumidity(atHPa: $0)
      ]
    }
  }

  static func temperature(atHPa levelHPa: Int) -> String { "temperature_\(levelHPa)hPa" }

  static func windSpeed(atHPa levelHPa: Int) -> String { "wind_speed_\(levelHPa)hPa" }

  static func windDirection(atHPa levelHPa: Int) -> String { "wind_direction_\(levelHPa)hPa" }

  /// The fraction of the sky a pressure level's cloud covers, as a percentage.
  static func cloudCover(atHPa levelHPa: Int) -> String { "cloud_cover_\(levelHPa)hPa" }

  /// The relative humidity at a pressure level, as a percentage.
  static func relativeHumidity(atHPa levelHPa: Int) -> String {
    "relative_humidity_\(levelHPa)hPa"
  }

  /// The geopotential height of a pressure level, which is the altitude its winds blow at.
  static func height(atHPa levelHPa: Int) -> String { "geopotential_height_\(levelHPa)hPa" }
}
