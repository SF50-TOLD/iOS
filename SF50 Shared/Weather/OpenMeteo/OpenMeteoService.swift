import CoreLocation
import Foundation
import Logging

/**
 * Actor that fetches forecasts from [Open-Meteo](https://open-meteo.com).
 *
 * Open-Meteo forecasts anywhere on earth, which is what makes it useful here: it fills the values
 * an aviation report leaves unreported, and supplies winds aloft where the NWS publishes none.
 *
 * ## Configuration
 *
 * The API key is optional and read from the app bundle's Info.plist as `OPEN_METEO_API_KEY`.
 * Without one the free endpoint is used, which is licensed for non-commercial use; with one, the
 * customer endpoint.
 *
 * ## Caching
 *
 * ``WeatherLoader`` recomputes every subscriber's conditions whenever any of its stores change, so
 * an uncached fetch here would mean a request per subscriber per change. One response covers three
 * days of hours for both surface and pressure-level data, and is reused until ``WeatherLoader``
 * next refreshes its downloads. Concurrent requests for the same airport await one fetch.
 *
 * A failure is held too, and for much less time: a service that can't be reached would otherwise be
 * asked again by every subscriber on every change, each attempt waiting out its own timeout.
 */
public actor OpenMeteoService {

  /// Shared singleton instance for app-wide Open-Meteo access.
  public static let shared = OpenMeteoService()

  /// The endpoint for requests without an API key, licensed for non-commercial use.
  private static let freeBaseURL = URL(string: "https://api.open-meteo.com")!

  /// The endpoint for requests authenticated with an API key.
  private static let customerBaseURL = URL(string: "https://customer-api.open-meteo.com")!

  /// How many days of hourly forecast to request.
  ///
  /// The response runs from 00:00Z today, so this reaches at least two days ahead — past the TAF
  /// horizon and past the day the winds aloft bulletins forecast for.
  private static let forecastDays = 3

  /// How long a fetch is given before it's abandoned.
  ///
  /// A forecast is a supplement, and a failed one leaves the aviation report as it stands, so it is
  /// not worth making the pilot wait out the sixty seconds a large download is allowed.
  private static let requestTimeout: TimeInterval = 30

  /// How long a failed fetch is remembered before the service is asked again.
  ///
  /// Far shorter than ``WeatherLoader/reloadInterval``: a forecast stays good for the whole
  /// interval, but a network that just failed may well be back. This only has to outlast the
  /// several rounds of subscriber notifications one load produces.
  private static let failureBackoff: TimeInterval = 60

  private static let logger = Logger(label: "codes.tim.SF50-TOLD.OpenMeteoService")

  private let baseURL: URL

  private let apiKey: String?

  private let decoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .secondsSince1970
    return decoder
  }()

  private let session: URLSession

  private var cache = [String: CachedOutcome]()

  private var fetches = [String: Task<OpenMeteoResponse, any Error>]()

  private init() {
    let key = Bundle.main.object(forInfoDictionaryKey: "OPEN_METEO_API_KEY") as? String
    apiKey = (key?.isEmpty ?? true) ? nil : key
    baseURL = apiKey == nil ? Self.freeBaseURL : Self.customerBaseURL

    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = Self.requestTimeout
    session = .init(configuration: configuration)
  }

  /// Conditions at an airport for a time, or `nil` if the forecast doesn't reach it.
  ///
  /// - Parameter key: Identifies the airport and time.
  /// - Returns: The forecast conditions.
  /// - Throws: `WeatherLoader.Errors` if the forecast couldn't be fetched.
  public func conditions(for key: WeatherLoader.Key) async throws -> Conditions? {
    .init(openMeteo: try await forecast(for: key), at: key.time)
  }

  /// Winds aloft at an airport for a time, or `nil` if the forecast doesn't reach it.
  ///
  /// - Parameter key: Identifies the airport and time.
  /// - Returns: The forecast winds aloft.
  /// - Throws: `WeatherLoader.Errors` if the forecast couldn't be fetched.
  public func windsAloft(for key: WeatherLoader.Key) async throws -> WindsAloftForecast? {
    .init(openMeteo: try await forecast(for: key), at: key.time)
  }

  /// Discards held outcomes, successful and failed alike, so the next request fetches afresh.
  public func invalidateCache() {
    cache.removeAll()
  }

  /// The forecast for an airport, fetching it only when no fresh outcome is already held.
  private func forecast(for key: WeatherLoader.Key) async throws -> OpenMeteoResponse {
    if let cached = cache[key.id], cached.isFresh { return try cached.result.get() }
    if let fetch = fetches[key.id] { return try await fetch.value }

    let fetch = Task { try await self.fetch(at: key.location.coordinate) }
    fetches[key.id] = fetch
    defer { fetches[key.id] = nil }

    do {
      let response = try await fetch.value
      remember(.success(response), for: key)
      return response
    } catch {
      // A cancelled fetch says nothing about whether the service can be reached.
      if !WeatherLoader.isNetworkCancellation(error) { remember(.failure(error), for: key) }
      throw error
    }
  }

  private func remember(
    _ result: Result<OpenMeteoResponse, any Error>,
    for key: WeatherLoader.Key
  ) {
    cache[key.id] = .init(result: result, fetchedAt: .now)
  }

  private func fetch(at coordinate: CLLocationCoordinate2D) async throws -> OpenMeteoResponse {
    let url = forecastURL(at: coordinate)
    Self.logger.info("Loading Open-Meteo forecast", metadata: ["url": "\(url)"])

    let (data, response) = try await session.data(from: url)
    try validate(response, from: data, url: url)

    do {
      return try decoder.decode(OpenMeteoResponse.self, from: data)
    } catch {
      Self.logger.error(
        "Failed to decode Open-Meteo forecast",
        metadata: ["error": "\(error)", "url": "\(url)"]
      )
      throw WeatherLoader.Errors.decodingFailed(url: url, underlyingError: error)
    }
  }

  /// Throws unless the response carries a forecast.
  ///
  /// Open-Meteo explains a rejected request in the body rather than the status line, so the body is
  /// read before the status code is judged: `reason` says which parameter it objected to. A
  /// forecast can't be mistaken for a rejection, since ``OpenMeteoErrorResponse`` requires both of
  /// its fields and a forecast carries neither.
  private func validate(_ response: URLResponse, from data: Data, url: URL) throws {
    guard !data.isEmpty else {
      Self.logger.error("Empty Open-Meteo response", metadata: ["url": "\(url)"])
      throw WeatherLoader.Errors.emptyResponse(url: url)
    }

    if let failure = try? decoder.decode(OpenMeteoErrorResponse.self, from: data), failure.error {
      Self.logger.error(
        "Open-Meteo rejected the request",
        metadata: ["reason": "\(failure.reason)", "url": "\(url)"]
      )
      throw WeatherLoader.Errors.serviceError(url: url, reason: failure.reason)
    }

    guard let response = response as? HTTPURLResponse,
      !(200..<300).contains(response.statusCode)
    else { return }

    Self.logger.error(
      "Bad HTTP response from Open-Meteo",
      metadata: ["statusCode": "\(response.statusCode)", "url": "\(url)"]
    )
    throw WeatherLoader.Errors.badResponse(response)
  }

  private func forecastURL(at coordinate: CLLocationCoordinate2D) -> URL {
    var components = URLComponents(
      url: baseURL.appending(path: "v1/forecast"),
      resolvingAgainstBaseURL: false
    )!
    components.queryItems = [
      .init(name: "latitude", value: coordinate.latitude.formatted(.coordinate)),
      .init(name: "longitude", value: coordinate.longitude.formatted(.coordinate)),
      .init(name: "hourly", value: OpenMeteoVariable.requested.joined(separator: ",")),
      .init(name: "wind_speed_unit", value: "kn"),
      .init(name: "temperature_unit", value: "celsius"),
      .init(name: "timeformat", value: "unixtime"),
      .init(name: "forecast_days", value: "\(Self.forecastDays)")
    ]
    if let apiKey {
      components.queryItems?.append(.init(name: "apikey", value: apiKey))
    }
    return components.url!
  }

  /// What a fetch came back with, held until it goes stale.
  ///
  /// A failure keeps its error rather than a flag, so a caller asking again inside the back-off
  /// window is told the same cause the network gave.
  private struct CachedOutcome {
    let result: Result<OpenMeteoResponse, any Error>
    let fetchedAt: Date

    var isFresh: Bool { fetchedAt.timeIntervalSinceNow > -lifetime }

    private var lifetime: TimeInterval {
      switch result {
        case .success: WeatherLoader.reloadInterval
        case .failure: OpenMeteoService.failureBackoff
      }
    }
  }
}

extension FormatStyle where Self == FloatingPointFormatStyle<Double> {
  /// Formats a latitude or longitude for a request.
  ///
  /// Four decimal places locate a point to about ten metres, which is finer than a forecast model's
  /// grid, and rounding to it lets requests from the same airport share Open-Meteo's cache.
  fileprivate static var coordinate: Self {
    .number.precision(.fractionLength(0...4)).grouping(.never).locale(.init(identifier: "en_US"))
  }
}
