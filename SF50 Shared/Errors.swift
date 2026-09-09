public import Foundation

extension PathAtmosphereLoader.Failure: LocalizedError {
  public var errorDescription: String? {
    String(localized: "Weather layers couldn’t be loaded", bundle: .sharedFramework)
  }

  public var failureReason: String? {
    switch self {
      case .offline:
        String(localized: "The forecast service couldn’t be reached.", bundle: .sharedFramework)
      case .unavailable:
        String(localized: "The forecast service couldn’t answer.", bundle: .sharedFramework)
    }
  }

  public var recoverySuggestion: String? {
    switch self {
      case .offline:
        String(
          localized: "Terrain, obstacles, and winds aloft still plot without a connection.",
          bundle: .sharedFramework
        )
      case .unavailable:
        String(localized: "Try again later.", bundle: .sharedFramework)
    }
  }
}

extension WeatherLoader.Errors: LocalizedError {
  public var errorDescription: String? {
    String(localized: "Weather information couldn’t be read", bundle: .sharedFramework)
  }

  public var failureReason: String? {
    switch self {
      case .badResponse(let response):
        String(
          localized: "Received HTTP response \(response.statusCode).",
          bundle: .sharedFramework
        )
      case .emptyResponse:
        String(localized: "The weather service sent an empty response.", bundle: .sharedFramework)
      case .gzipDecompressionFailed:
        String(
          localized: "Downloaded weather data was corrupted or incomplete.",
          bundle: .sharedFramework
        )
      case .invalidTextEncoding:
        String(
          localized: "Downloaded weather data had an invalid text encoding.",
          bundle: .sharedFramework
        )
      case .unresolvableForecastPeriod:
        String(
          localized: "A winds aloft forecast didn’t say when it applies.",
          bundle: .sharedFramework
        )
      case .decodingFailed:
        String(
          localized: "Downloaded weather data wasn’t in the expected format.",
          bundle: .sharedFramework
        )
      case .serviceError(_, let reason):
        String(
          localized: "The weather service refused the request: \(reason)",
          bundle: .sharedFramework
        )
    }
  }

  public var recoverySuggestion: String? {
    String(
      localized: "Try re-downloading weather data later, or manually enter weather.",
      bundle: .sharedFramework
    )
  }
}

extension PerformanceLookupError: LocalizedError {
  public var errorDescription: String? {
    String(
      localized: "Takeoff and landing numbers couldn’t be calculated",
      bundle: .sharedFramework
    )
  }

  public var failureReason: String? {
    switch self {
      case .navigationDataOutOfDate:
        String(localized: "The airport database needs to be reloaded.", bundle: .sharedFramework)
      case .noAirportSelected:
        String(localized: "No airport has been selected.", bundle: .sharedFramework)
      case .airportNotFound:
        String(localized: "That airport isn’t in the database.", bundle: .sharedFramework)
      case .noRunwaySelected:
        String(localized: "No runway has been selected.", bundle: .sharedFramework)
      case .runwayNotFound(let name, let airport):
        String(localized: "\(airport) has no runway \(name).", bundle: .sharedFramework)
      case .weatherUnavailable(let airport):
        String(localized: "No weather could be loaded for \(airport).", bundle: .sharedFramework)
    }
  }

  public var recoverySuggestion: String? {
    switch self {
      case .navigationDataOutOfDate:
        String(
          localized: "Open SF50 TOLD and let it finish loading airport data.",
          bundle: .sharedFramework
        )
      case .noAirportSelected:
        String(
          localized: "Choose an airport in SF50 TOLD, or name one in the shortcut.",
          bundle: .sharedFramework
        )
      case .noRunwaySelected:
        String(
          localized: "Choose a runway in SF50 TOLD, or name one in the shortcut.",
          bundle: .sharedFramework
        )
      case .airportNotFound, .runwayNotFound:
        String(
          localized: "Check the identifier, or reload airport data in SF50 TOLD.",
          bundle: .sharedFramework
        )
      case .weatherUnavailable:
        String(localized: "Try again once a connection is available.", bundle: .sharedFramework)
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
    return .init("\(sentences.joined(separator: " "))", bundle: .sharedFramework)
  }
}
