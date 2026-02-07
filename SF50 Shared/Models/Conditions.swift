import CoreLocation
import Foundation
import SwiftMETAR
import WeatherKit

/// Atmospheric conditions used for performance calculations.
///
/// ``Conditions`` represents weather observations or forecasts including wind,
/// temperature, dewpoint, and pressure. Conditions can be sourced from METAR,
/// TAF, WeatherKit forecasts, or manually entered by the user.
public struct Conditions: Sendable, Equatable {
  /// Time interval during which these conditions are valid.
  public let validTime: DateInterval

  /// Data source for these conditions.
  public let source: Source

  /// Wind direction in degrees true, or `nil` for variable winds.
  public let windDirection: Measurement<UnitAngle>?

  /// Wind speed, or `nil` if not reported.
  public let windSpeed: Measurement<UnitSpeed>?

  /// Temperature, or `nil` if not reported.
  public let temperature: Measurement<UnitTemperature>?

  /// Dewpoint temperature, or `nil` if not reported.
  public let dewpoint: Measurement<UnitTemperature>?

  /// Sea level pressure, or `nil` if not reported.
  public let seaLevelPressure: Measurement<UnitPressure>?

  /// Whether winds are calm (less than 1 knot or not reported).
  public var windsCalm: Bool {
    windSpeed.map { $0 < Measurement(value: 1, unit: UnitSpeed.knots) } ?? true
  }

  private init(
    validTime: DateInterval,
    source: Source,
    windDirection: Measurement<UnitAngle>?,
    windSpeed: Measurement<UnitSpeed>?,
    temperature: Measurement<UnitTemperature>?,
    dewpoint: Measurement<UnitTemperature>?,
    seaLevelPressure: Measurement<UnitPressure>?
  ) {
    self.validTime = validTime
    self.source = source
    self.windDirection = windDirection
    self.windSpeed = windSpeed
    self.temperature = temperature
    self.dewpoint = dewpoint
    self.seaLevelPressure = seaLevelPressure
  }

  /**
   * Creates conditions with manually entered values.
   *
   * - Parameters:
   *   - windDirection: Wind direction in degrees true.
   *   - windSpeed: Wind speed.
   *   - temperature: Temperature.
   *   - seaLevelPressure: Sea level pressure (altimeter setting).
   */
  public init(
    windDirection: Measurement<UnitAngle>? = nil,
    windSpeed: Measurement<UnitSpeed>? = nil,
    temperature: Measurement<UnitTemperature>? = nil,
    seaLevelPressure: Measurement<UnitPressure>? = nil
  ) {
    validTime = .init(start: .now, duration: 3600)
    self.windDirection = windDirection
    self.windSpeed = windSpeed
    self.temperature = temperature
    dewpoint = nil
    self.seaLevelPressure = seaLevelPressure
    source = .entered
  }

  /// Creates conditions from a SwiftMETAR observation.
  public init(observation: SwiftMETAR.METAR) {
    validTime = .init(start: observation.date, duration: 3600)

    switch observation.wind {
      case .calm:
        windDirection = .init(value: 0, unit: .degrees)
        windSpeed = .init(value: 0, unit: .knots)
      case .variable(let speed, _):
        windDirection = nil  // Variable wind
        windSpeed = speed.measurement
      case .direction(let heading, let speed, _):
        windDirection = .init(value: Double(heading), unit: .degrees)
        windSpeed = speed.measurement
      case .directionRange(let heading, _, let speed, _):
        windDirection = .init(value: Double(heading), unit: .degrees)
        windSpeed = speed.measurement
      case .none:
        windDirection = nil
        windSpeed = nil
    }

    temperature = observation.temperatureMeasurement
    dewpoint = observation.dewpointMeasurement
    seaLevelPressure = observation.altimeter?.measurement

    source = .NWS
  }

  /// Creates conditions from a SwiftMETAR TAF group, or `nil` if the forecast period is invalid.
  public init?(forecast: SwiftMETAR.TAF.Group) {
    // Extract DateInterval from the period enum
    let interval: DateInterval
    switch forecast.period {
      case .range(let period):
        interval = period.dateInterval
      case .from(let from):
        guard let fromDate = from.date else { return nil }
        interval = DateInterval(start: fromDate, duration: 86400)  // 24h default
      case .temporary(let period):
        interval = period.dateInterval
      case .becoming(let period):
        interval = period.dateInterval
      case .probability(_, let period):
        interval = period.dateInterval
    }
    validTime = interval

    switch forecast.wind {
      case .calm:
        windDirection = .init(value: 0, unit: .degrees)
        windSpeed = .init(value: 0, unit: .knots)
      case .variable(let speed, _):
        windDirection = nil  // Variable wind
        windSpeed = speed.measurement
      case .direction(let heading, let speed, _):
        windDirection = .init(value: Double(heading), unit: .degrees)
        windSpeed = speed.measurement
      case .directionRange(let heading, _, let speed, _):
        windDirection = .init(value: Double(heading), unit: .degrees)
        windSpeed = speed.measurement
      case .none:
        windDirection = nil
        windSpeed = nil
    }

    temperature = nil
    dewpoint = nil
    seaLevelPressure = forecast.altimeter?.measurement

    source = .NWS
  }

  /// Creates conditions from WeatherKit current weather.
  public init(weather: CurrentWeather) {
    validTime = .init(start: weather.date, duration: 3600)

    windDirection = weather.wind.direction
    windSpeed = weather.wind.speed
    temperature = weather.temperature
    dewpoint = weather.dewPoint
    seaLevelPressure = weather.pressure
    source = .WeatherKit
  }

  /// Creates conditions from WeatherKit hourly forecast.
  public init(weather: HourWeather) {
    validTime = .init(start: weather.date, duration: 3600)

    windDirection = weather.wind.direction
    windSpeed = weather.wind.speed
    temperature = weather.temperature
    dewpoint = weather.dewPoint
    seaLevelPressure = weather.pressure
    source = .WeatherKit
  }

  /// Creates ISA standard conditions (sea level, 15°C, 1013.25 hPa, calm winds).
  public init() {
    validTime = .init(start: .now, duration: 3600)
    windDirection = .init(value: 0, unit: .degrees)
    windSpeed = .init(value: 0, unit: .knots)
    temperature = standardTemperature
    dewpoint = nil
    seaLevelPressure = standardSeaLevelPressure
    source = .ISA
  }

  /// Returns conditions with missing values filled from WeatherKit current weather.
  func adding(weather: CurrentWeather) -> Self {
    .init(
      validTime: validTime,
      source: .augmented,
      windDirection: windDirection ?? weather.wind.direction,
      windSpeed: windSpeed ?? weather.wind.speed,
      temperature: temperature ?? weather.temperature,
      dewpoint: dewpoint ?? weather.dewPoint,
      seaLevelPressure: seaLevelPressure ?? weather.pressure
    )
  }

  /// Returns conditions with missing values filled from WeatherKit hourly forecast.
  func adding(weather: HourWeather) -> Self {
    .init(
      validTime: validTime,
      source: .augmented,
      windDirection: windDirection ?? weather.wind.direction,
      windSpeed: windSpeed ?? weather.wind.speed,
      temperature: temperature ?? weather.temperature,
      dewpoint: dewpoint ?? weather.dewPoint,
      seaLevelPressure: seaLevelPressure ?? weather.pressure
    )
  }

  /// Returns conditions with missing values filled from another conditions instance.
  public func adding(conditions: Self) -> Self {
    .init(
      validTime: validTime,
      source: conditions.source,
      windDirection: conditions.windDirection ?? windDirection,
      windSpeed: conditions.windSpeed ?? windSpeed,
      temperature: conditions.temperature ?? temperature,
      dewpoint: conditions.dewpoint ?? dewpoint,
      seaLevelPressure: conditions.seaLevelPressure ?? seaLevelPressure
    )
  }

  /// Returns conditions modified by user-entered values, changing the source to `.entered`.
  public func userModified(with conditions: Self) -> Self {
    .init(
      validTime: validTime,
      source: .entered,
      windDirection: conditions.windDirection ?? windDirection,
      windSpeed: conditions.windSpeed ?? windSpeed,
      temperature: conditions.temperature ?? temperature,
      dewpoint: conditions.dewpoint ?? dewpoint,
      seaLevelPressure: conditions.seaLevelPressure ?? seaLevelPressure
    )
  }

  /// Returns the temperature at the given elevation, using ISA lapse rate if not reported.
  public func temperature(at elevation: Measurement<UnitLength>) -> Measurement<UnitTemperature> {
    if source == .ISA {
      return ISATemperature(at: elevation)
    }
    return temperature ?? ISATemperature(at: elevation)
  }

  /// Calculates density altitude at the given elevation using NWS dry-air formula.
  public func densityAltitude(elevation: Measurement<UnitLength>) -> Measurement<UnitLength> {
    let stationPressureInHg = absolutePressure(elevation: elevation)
      .converted(to: .inchesOfMercury).value
    let tempDegF = temperature(at: elevation).converted(to: .fahrenheit).value

    let DA = SF50_Shared.densityAltitude(
      stationPressureInHg: stationPressureInHg,
      temperatureF: tempDegF
    )
    return .init(value: DA, unit: .feet)
  }

  private func ISATemperature(at altitude: Measurement<UnitLength>) -> Measurement<UnitTemperature>
  {
    let altFt = altitude.converted(to: .feet).value
    return .init(value: isaTemperature(altitudeFt: altFt), unit: .celsius)
  }

  private func absolutePressure(elevation: Measurement<UnitLength>) -> Measurement<UnitPressure> {
    let SLP = seaLevelPressure ?? .init(value: standardSeaLevelPressureHPa, unit: .hectopascals)
    return pressure(altimeter: SLP, altitude: elevation)
  }

  private func pressure(altimeter: Measurement<UnitPressure>, altitude: Measurement<UnitLength>)
    -> Measurement<UnitPressure>
  {
    let slpPa = altimeter.converted(to: .hectopascals).value * 100
    let altM = altitude.converted(to: .meters).value

    let pressurePa = pressureAtAltitude(seaLevelPressurePa: slpPa, altitudeM: altM)
    return .init(value: pressurePa / 100, unit: .hectopascals)
  }

  /// Data source for weather conditions.
  public enum Source: Sendable {
    /// National Weather Service (METAR/TAF).
    case NWS
    /// Apple WeatherKit.
    case WeatherKit
    /// NWS data augmented with WeatherKit.
    case augmented
    /// International Standard Atmosphere defaults.
    case ISA
    /// Manually entered by user.
    case entered
  }
}
