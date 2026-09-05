public import Foundation

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

extension PerformanceLookupError: LocalizedError {
  public var errorDescription: String? {
    String(localized: "Takeoff and landing numbers couldn’t be calculated")
  }

  public var failureReason: String? {
    switch self {
      case .navigationDataOutOfDate:
        String(localized: "The airport database needs to be reloaded.")
      case .noAirportSelected:
        String(localized: "No airport has been selected.")
      case .airportNotFound:
        String(localized: "That airport isn’t in the database.")
      case .noRunwaySelected:
        String(localized: "No runway has been selected.")
      case .runwayNotFound(let name, let airport):
        String(localized: "\(airport) has no runway \(name).")
      case .weatherUnavailable(let airport):
        String(localized: "No weather could be loaded for \(airport).")
    }
  }

  public var recoverySuggestion: String? {
    switch self {
      case .navigationDataOutOfDate:
        String(localized: "Open SF50 TOLD and let it finish loading airport data.")
      case .noAirportSelected:
        String(localized: "Choose an airport in SF50 TOLD, or name one in the shortcut.")
      case .noRunwaySelected:
        String(localized: "Choose a runway in SF50 TOLD, or name one in the shortcut.")
      case .airportNotFound, .runwayNotFound:
        String(localized: "Check the identifier, or reload airport data in SF50 TOLD.")
      case .weatherUnavailable:
        String(localized: "Try again once a connection is available.")
    }
  }
}

extension PerformanceLookupError: CustomLocalizedStringResourceConvertible {
  /// What Shortcuts and Siri say when the intent refuses.
  ///
  /// App Intents shows a thrown error's own wording only through this conformance — a `LocalizedError`
  /// alone gets the system's generic “couldn’t run”, which tells a pilot nothing about which of these
  /// refusals happened or what to do about it.
  public var localizedStringResource: LocalizedStringResource {
    let sentences = [failureReason, recoverySuggestion].compactMap(\.self)
    return "\(sentences.joined(separator: " "))"
  }
}
