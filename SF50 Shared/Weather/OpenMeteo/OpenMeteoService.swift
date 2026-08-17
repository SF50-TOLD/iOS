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

  private static let secondsPerHour: TimeInterval = 3600,
    secondsPerDay: TimeInterval = 86400

  /// How far either side of the requested hour a profile request reaches.
  ///
  /// One hour of slack costs almost nothing and spares the request from turning up empty when the
  /// requested time falls on an hour boundary the model rounds the other way.
  private static let hourSlack = secondsPerHour

  /// How long a fetch is given before it's abandoned.
  ///
  /// A forecast is a supplement, and a failed one leaves the aviation report as it stands, so it is
  /// not worth making the pilot wait out the sixty seconds a large download is allowed.
  private static let requestTimeout: TimeInterval = 30

  /// How long a profile request waits before giving up.
  ///
  /// Shorter still than ``requestTimeout``. The layers it feeds are optional context, and a
  /// go-around profile is often planned in the air with no connection at all — where a quick refusal
  /// the UI can act on beats waiting out the longer timeout.
  private static let profileTimeout: TimeInterval = 10

  /// How long a failed fetch is remembered before the service is asked again.
  ///
  /// Far shorter than ``WeatherLoader/reloadInterval``: a forecast stays good for the whole
  /// interval, but a network that just failed may well be back. This only has to outlast the
  /// several rounds of subscriber notifications one load produces.
  private static let failureBackoff: TimeInterval = 60

  private static let logger = Logger(label: "codes.tim.SF50-TOLD.OpenMeteoService")

  /// The hours a request may ask for.
  ///
  /// The response runs from midnight UTC today, and a `start_hour` outside that range is rejected
  /// outright where `forecast_days` merely answers with no hour covering the time. Profile requests
  /// are clamped into this window and a time beyond it is refused without a round trip, so a date
  /// past the horizon reads the same on both paths: a forecast that doesn't reach it, rather than a
  /// service that couldn't answer.
  private static var forecastWindow: ClosedRange<Date> {
    let firstHour = Date.now.startOfDayUTC
    return
      firstHour...firstHour.addingTimeInterval(
        Double(forecastDays) * secondsPerDay - secondsPerHour
      )
  }

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

  /// Atmospheric profiles above a set of points, for a time.
  ///
  /// Open-Meteo answers for many coordinates in one request, so a path needing several columns costs
  /// one round trip rather than one per column. The request is bounded to the hours around `time`
  /// rather than the three days ``conditions(for:)`` asks for, and leaves out the surface variables,
  /// which keeps a two-dozen-column response to a few tens of kilobytes.
  ///
  /// - Parameters:
  ///   - coordinates: The points to profile.
  ///   - time: The time the profiles are needed for.
  /// - Returns: A profile per coordinate, in the order asked for, `nil` where the forecast doesn't
  ///   reach the time or reports no usable level.
  /// - Throws: `WeatherLoader.Errors` if the forecast couldn't be fetched.
  public func profiles(
    at coordinates: [CLLocationCoordinate2D],
    for time: Date
  ) async throws -> [AtmosphericProfile?] {
    guard !coordinates.isEmpty else { return [] }
    guard Self.forecastWindow.contains(time.startOfHour) else {
      Self.logger.info(
        "Time lies outside the Open-Meteo forecast window",
        metadata: ["time": "\(time)"]
      )
      return coordinates.map { _ in nil }
    }

    let url = profileURL(at: coordinates, for: time)
    Self.logger.info(
      "Loading Open-Meteo profiles",
      metadata: ["columns": "\(coordinates.count)", "url": "\(url)"]
    )

    var request = URLRequest(url: url)
    request.timeoutInterval = Self.profileTimeout

    let (data, response) = try await session.data(for: request)
    try validate(response, from: data, url: url)

    let responses: [OpenMeteoResponse]
    do {
      responses = try decodeProfileResponses(from: data)
    } catch {
      Self.logger.error(
        "Failed to decode Open-Meteo profiles",
        metadata: ["error": "\(error)", "url": "\(url)"]
      )
      throw WeatherLoader.Errors.decodingFailed(url: url, underlyingError: error)
    }

    return zip(coordinates, responses).map { coordinate, response in
      .init(openMeteo: response, at: coordinate, for: time)
    }
  }

  /// Discards held outcomes, successful and failed alike, so the next request fetches afresh.
  public func invalidateCache() {
    cache.removeAll()
  }

  /// Decodes a forecast response that may describe one location or many.
  ///
  /// Open-Meteo answers a single coordinate with an object and several with an array of them, so
  /// both shapes are accepted and a lone object is read as a list of one.
  private func decodeProfileResponses(from data: Data) throws -> [OpenMeteoResponse] {
    do {
      return try decoder.decode([OpenMeteoResponse].self, from: data)
    } catch DecodingError.typeMismatch {
      return [try decoder.decode(OpenMeteoResponse.self, from: data)]
    }
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
      .init(name: "latitude", value: coordinate.latitude.openMeteoCoordinate),
      .init(name: "longitude", value: coordinate.longitude.openMeteoCoordinate),
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

  private func profileURL(at coordinates: [CLLocationCoordinate2D], for time: Date) -> URL {
    var components = URLComponents(
      url: baseURL.appending(path: "v1/forecast"),
      resolvingAgainstBaseURL: false
    )!
    let hour = time.startOfHour,
      window = Self.forecastWindow
    let startHour = max(hour.addingTimeInterval(-Self.hourSlack), window.lowerBound),
      endHour = min(hour.addingTimeInterval(Self.hourSlack), window.upperBound)
    components.queryItems = [
      .init(
        name: "latitude",
        value: coordinates.map(\.latitude.openMeteoCoordinate).joined(separator: ",")
      ),
      .init(
        name: "longitude",
        value: coordinates.map(\.longitude.openMeteoCoordinate).joined(separator: ",")
      ),
      .init(name: "hourly", value: OpenMeteoVariable.profileRequested.joined(separator: ",")),
      .init(name: "temperature_unit", value: "celsius"),
      .init(name: "timeformat", value: "unixtime"),
      .init(name: "start_hour", value: startHour.openMeteoHour),
      .init(name: "end_hour", value: endHour.openMeteoHour)
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

extension Date {
  /// Writes a time the way `start_hour` and `end_hour` expect it: UTC, to the minute, without a
  /// zone suffix.
  ///
  /// Open-Meteo reads this, not a person, so it is pinned to a fixed format on the POSIX locale and
  /// says the same thing under every locale and calendar the app runs in.
  ///
  /// `ISO8601DateFormatter` can't serve: it always writes the seconds this format leaves out.
  private static var openMeteoHourFormatter: DateFormatter {
    let formatter = DateFormatter()
    formatter.locale = .init(identifier: "en_US_POSIX")
    formatter.timeZone = .gmt
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
    return formatter
  }

  /// The calendar Open-Meteo lays its hours out on: Gregorian days beginning at midnight UTC,
  /// whatever the device is set to.
  private static var utcCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    return calendar
  }

  /// Midnight UTC on the day this time falls in, where a forecast's hours start.
  var startOfDayUTC: Self { Self.utcCalendar.startOfDay(for: self) }

  /// This time truncated to the hour it falls in.
  var startOfHour: Self {
    .init(timeIntervalSinceReferenceDate: timeIntervalSinceReferenceDate.rounded(.down) - remainder)
  }

  private var remainder: TimeInterval {
    timeIntervalSinceReferenceDate.rounded(.down).truncatingRemainder(dividingBy: 3600)
  }

  /// This time as `start_hour` and `end_hour` expect it.
  fileprivate var openMeteoHour: String { Self.openMeteoHourFormatter.string(from: self) }
}

extension Double {
  /// This latitude or longitude as a request writes it.
  ///
  /// Open-Meteo reads this, not a person, so it is written with `String(format:)`, which is
  /// independent of locale and so of whichever decimal separator, digits, and grouping the device
  /// is set to.
  ///
  /// Four decimal places locate a point to about ten metres, which is finer than a forecast model's
  /// grid, and rounding to it lets requests from the same airport share Open-Meteo's cache.
  fileprivate var openMeteoCoordinate: String { .init(format: "%.4f", self) }
}
