public import Foundation
public import SwiftMETAR
public import WeatherKit

extension Conditions {
  private static let observationValidity: TimeInterval = 3600,
    openEndedForecastValidity: TimeInterval = 86400

  /// Creates conditions from a SwiftMETAR observation.
  public init(observation: SwiftMETAR.METAR) {
    let (windDirection, windSpeed) = Self.wind(observation.wind)
    self.init(
      validTime: .init(start: observation.date, duration: Self.observationValidity),
      source: .downloaded(.NWS),
      windDirection: windDirection,
      windSpeed: windSpeed,
      temperature: observation.temperatureMeasurement,
      dewpoint: observation.dewpointMeasurement,
      seaLevelPressure: observation.altimeter?.measurement
    )
  }

  /// Creates conditions from a SwiftMETAR TAF group, or `nil` if the forecast period is invalid.
  ///
  /// A TAF forecasts no temperature or dewpoint, so both are left unreported.
  public init?(forecast: SwiftMETAR.TAF.Group) {
    guard let validTime = Self.validTime(of: forecast.period) else { return nil }
    let (windDirection, windSpeed) = Self.wind(forecast.wind)
    self.init(
      validTime: validTime,
      source: .downloaded(.NWS),
      windDirection: windDirection,
      windSpeed: windSpeed,
      temperature: nil,
      dewpoint: nil,
      seaLevelPressure: forecast.altimeter?.measurement
    )
  }

  /// Creates conditions from WeatherKit current weather.
  public init(weather: CurrentWeather) {
    self.init(
      validTime: .init(start: weather.date, duration: Self.observationValidity),
      source: .downloaded(.weatherKit),
      windDirection: weather.wind.direction,
      windSpeed: weather.wind.speed,
      temperature: weather.temperature,
      dewpoint: weather.dewPoint,
      seaLevelPressure: weather.pressure
    )
  }

  /// Creates conditions from WeatherKit hourly forecast.
  public init(weather: HourWeather) {
    self.init(
      validTime: .init(start: weather.date, duration: Self.observationValidity),
      source: .downloaded(.weatherKit),
      windDirection: weather.wind.direction,
      windSpeed: weather.wind.speed,
      temperature: weather.temperature,
      dewpoint: weather.dewPoint,
      seaLevelPressure: weather.pressure
    )
  }

  /// Creates fake NWS-sourced conditions for UI testing.
  public static func fakeNWS(
    windDirection: Measurement<UnitAngle> = .init(value: 350, unit: .degrees),
    windSpeed: Measurement<UnitSpeed> = .init(value: 15, unit: .knots),
    temperature: Measurement<UnitTemperature> = .init(value: 21, unit: .celsius),
    seaLevelPressure: Measurement<UnitPressure> = .init(value: 30.05, unit: .inchesOfMercury)
  ) -> Self {
    .init(
      validTime: .init(start: .now, duration: observationValidity),
      source: .downloaded(.NWS),
      windDirection: windDirection,
      windSpeed: windSpeed,
      temperature: temperature,
      dewpoint: nil,
      seaLevelPressure: seaLevelPressure
    )
  }

  /// The wind direction and speed a report gives. A variable wind has a speed and no direction.
  private static func wind(
    _ wind: SwiftMETAR.Wind?
  ) -> (direction: Measurement<UnitAngle>?, speed: Measurement<UnitSpeed>?) {
    switch wind {
      case .calm:
        (.init(value: 0, unit: .degrees), .init(value: 0, unit: .knots))
      case .variable(let speed, _):
        (nil, speed.measurement)
      case .direction(let heading, let speed, _):
        (.init(value: Double(heading), unit: .degrees), speed.measurement)
      case .directionRange(let heading, _, let speed, _):
        (.init(value: Double(heading), unit: .degrees), speed.measurement)
      case .none:
        (nil, nil)
    }
  }

  /// The period a TAF group covers, or `nil` for a `FM` group whose start cannot be dated.
  private static func validTime(of period: SwiftMETAR.TAF.Group.Period) -> DateInterval? {
    switch period {
      case .range(let period):
        return period.dateInterval
      case .from(let from):
        guard let fromDate = from.date else { return nil }
        return DateInterval(start: fromDate, duration: openEndedForecastValidity)
      case .temporary(let period):
        return period.dateInterval
      case .becoming(let period):
        return period.dateInterval
      case .probability(_, let period):
        return period.dateInterval
    }
  }
}
