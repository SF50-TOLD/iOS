import Foundation
import Sentry
@preconcurrency import WeatherKit

extension WeatherLoader {
  func conditions(for key: Key) async -> Loadable<Conditions> {
    let weather: WeatherKit.Weather?
    do {
      weather = try await Self.weatherService.weather(for: key.location)
    } catch {
      if Self.isNetworkCancellation(error) {
        // No action needed
      } else if Self.isTransientNetworkError(error) {
        Self.logger.info(
          "Transient network error fetching WeatherKit data",
          metadata: [
            "error": "\(error)",
            "id": "\(key.id)"
          ]
        )
      } else {
        SentrySDK.capture(error: error) { scope in
          scope.setLevel(.warning)
          scope.setTag(value: "weatherKit", key: "weather.dataType")
          scope.setTag(value: key.id, key: "airport")
          scope.setFingerprint(["weather-loading", "weatherKit"])
        }
        Self.logger.error(
          "WeatherKit error",
          metadata: [
            "error": "\(error)",
            "location": "\(key.location)",
            "id": "\(key.id)"
          ]
        )
      }
      weather = nil
    }

    if key.time.timeIntervalSinceNow < 3600 {
      return observations.map { observations in
        if let conditions = observations[key.id]?.conditions {
          if let weather {
            return conditions.adding(weather: weather.currentWeather)
          }
          return conditions
        }
        if let weather {
          return .init(weather: weather.currentWeather)
        }
        return .init()
      }
    }
    return forecasts.map { forecasts in
      let forecast = forecasts[key.id]
      if let conditions = forecast?.conditions.first(where: { $0.validTime.contains(key.time) }) {
        if let weather, let hourly = weather.hourlyForecast.for(date: key.time) {
          return conditions.adding(weather: hourly)
        }
        return conditions
      }
      if let weather, let hourly = weather.hourlyForecast.for(date: key.time) {
        return .init(weather: hourly)
      }
      return .init()
    }
  }
}
