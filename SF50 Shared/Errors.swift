import Foundation

extension PathAtmosphereLoader.Failure: LocalizedError {
  public var errorDescription: String? {
    String(localized: "Weather layers couldn’t be loaded")
  }

  public var failureReason: String? {
    switch self {
      case .offline:
        String(localized: "The forecast service couldn’t be reached.")
      case .unavailable:
        String(localized: "The forecast service couldn’t answer.")
    }
  }

  public var recoverySuggestion: String? {
    switch self {
      case .offline:
        String(localized: "Terrain, obstacles, and winds aloft still plot without a connection.")
      case .unavailable:
        String(localized: "Try again later.")
    }
  }
}

extension WeatherLoader.Errors: LocalizedError {
  public var errorDescription: String? {
    String(localized: "Weather information couldn’t be read")
  }

  public var failureReason: String? {
    switch self {
      case .badResponse(let response):
        String(localized: "Received HTTP response \(response.statusCode).")
      case .emptyResponse:
        String(localized: "The weather service sent an empty response.")
      case .gzipDecompressionFailed:
        String(localized: "Downloaded weather data was corrupted or incomplete.")
      case .invalidTextEncoding:
        String(localized: "Downloaded weather data had an invalid text encoding.")
      case .unresolvableForecastPeriod:
        String(localized: "A winds aloft forecast didn’t say when it applies.")
      case .decodingFailed:
        String(localized: "Downloaded weather data wasn’t in the expected format.")
      case .serviceError(_, let reason):
        String(localized: "The weather service refused the request: \(reason)")
    }
  }

  public var recoverySuggestion: String? {
    String(localized: "Try re-downloading weather data later, or manually enter weather.")
  }
}
