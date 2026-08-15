import CoreLocation
import Foundation
import Logging
@preconcurrency import WeatherKit

/// Protocol defining the weather loading interface.
///
/// ``WeatherLoaderProtocol`` provides a testable abstraction for loading weather data
/// from METAR/TAF sources and Apple WeatherKit. Implementations must be actors to
/// ensure thread-safe access to cached data.
public protocol WeatherLoaderProtocol: Actor {
  /// Loads weather data, optionally forcing a refresh.
  /// - Parameter force: If true, ignores cache and reloads from network.
  func load(force: Bool) async

  /// Cancels any in-progress loading operation.
  func cancelLoading()

  /// Creates a stream of conditions updates for the given key.
  /// - Parameter key: Identifies the airport and time to monitor.
  /// - Returns: Async stream yielding conditions as they become available.
  func streamConditions(for key: WeatherLoader.Key) async -> AsyncStream<Loadable<Conditions>>

  /// Creates a stream of raw METAR text updates.
  /// - Parameter key: Identifies the airport to monitor.
  /// - Returns: Async stream yielding METAR text as it becomes available.
  func streamMETAR(for key: WeatherLoader.Key) async -> AsyncStream<Loadable<String?>>

  /// Creates a stream of raw TAF text updates.
  /// - Parameter key: Identifies the airport to monitor.
  /// - Returns: Async stream yielding TAF text as it becomes available.
  func streamTAF(for key: WeatherLoader.Key) async -> AsyncStream<Loadable<String?>>

  /// Creates a stream of winds aloft data updates.
  /// - Parameter key: Identifies the airport and time to monitor.
  /// - Returns: Async stream yielding winds aloft data as it becomes available.
  ///   Returns `nil` for airports without a winds aloft reporting station, and for times no
  ///   loaded forecast period covers.
  func streamWindsAloft(for key: WeatherLoader.Key) async
    -> AsyncStream<Loadable<WindsAloftForecast?>>
}

/**
 * Actor responsible for loading and caching weather data from multiple sources.
 *
 * ``WeatherLoader`` downloads METAR observations, TAF forecasts and winds aloft bulletins from
 * Aviation Weather (aviationweather.gov) and supplements them with forecast model data. It provides
 * reactive streams of weather conditions that update when new data is loaded.
 *
 * ## Data Sources
 *
 * Weather data is combined from, in order of authority:
 * - **Aviation Weather**: METAR observations, TAF forecasts and winds aloft bulletins
 * - **Open-Meteo**: A forecast model, which fills gaps in aviation data and covers the places and
 *   times the NWS publishes no winds aloft for
 * - **WeatherKit**: Current conditions and hourly forecasts, where Open-Meteo couldn't answer
 *
 * ## Time-Based Conditions
 *
 * The loader automatically selects the appropriate data source based on time:
 * - **Current** (within 1 hour): Uses METAR observation, supplemented by the forecast models
 * - **Future**: Uses TAF forecast period covering the requested time, likewise supplemented
 *
 * ## Subscription Model
 *
 * Weather data is delivered via `AsyncStream`:
 * - ``streamConditions(for:)`` - Complete ``Conditions`` objects
 * - ``streamMETAR(for:)`` - Raw METAR text
 * - ``streamTAF(for:)`` - Raw TAF text
 */
public actor WeatherLoader: WeatherLoaderProtocol {
  /// Shared singleton instance for app-wide weather loading.
  public static let shared = WeatherLoader()

  private static let reloadIntervalMinutes: Double = 15
  static let reloadInterval = 60.0 * reloadIntervalMinutes
  static let METARsURL = URL(
    string: "https://aviationweather.gov/data/cache/metars.cache.xml.gz"
  )!
  static let TAFsURL = URL(
    string: "https://aviationweather.gov/data/cache/tafs.cache.xml.gz"
  )!
  /// The forecast periods, in hours, the NWS publishes a low-level winds aloft bulletin for.
  static let windsAloftForecastHours = [6, 12, 24]
  static let logger = Logger(label: "codes.tim.SF50-TOLD.WeatherLoader")
  static let weatherService = WeatherService()

  var observations: Loadable<[String: Observation]> = .notLoaded {
    didSet { Task { await notifySubscribers() } }
  }
  var forecasts: Loadable<[String: Forecast]> = .notLoaded {
    didSet { Task { await notifySubscribers() } }
  }
  var windsAloft: Loadable<[WindsAloftBulletin]> = .notLoaded {
    didSet { Task { await notifySubscribers() } }
  }
  /// Why part of the last winds aloft load failed, when the rest of it succeeded.
  ///
  /// The bulletins that did arrive are still published, so the failure is only visible to a pilot
  /// in the part of the country the missing ones cover; see ``windsAloftForecast(for:)``.
  var windsAloftPartialFailure: (any Error)?
  var lastLoaded: Date?
  var conditionsSubscribers = [
    UUID: (Key, AsyncStream<Loadable<Conditions>>.Continuation)
  ]()
  var metarSubscribers = [UUID: (Key, AsyncStream<Loadable<String?>>.Continuation)]()
  var tafSubscribers = [UUID: (Key, AsyncStream<Loadable<String?>>.Continuation)]()
  var windsAloftSubscribers = [
    UUID: (Key, AsyncStream<Loadable<WindsAloftForecast?>>.Continuation)
  ]()
  var loadingTask: Task<Void, Never>?

  var session: URLSession { .init(configuration: .ephemeral) }

  private init() {}

  /// The Aviation Weather URL for a low-level winds aloft bulletin.
  /// - Parameters:
  ///   - forecastHour: The forecast period, in hours; see ``windsAloftForecastHours``.
  ///   - region: The area the bulletin covers.
  /// - Returns: The URL of that region's bulletin for that period.
  static func windsAloftURL(forecastHour: Int, region: WindsAloftRegion) -> URL {
    .init(
      string: "https://aviationweather.gov/api/data/windtemp?level=low"
        + "&fcst=\(String(format: "%02d", forecastHour))&region=\(region.rawValue)&layout=on"
    )!
  }

  public func load(force: Bool = false) async {
    if !force, let lastLoaded, lastLoaded.timeIntervalSinceNow > -Self.reloadInterval {
      return
    }
    loadingTask?.cancel()
    loadingTask = Task {
      await OpenMeteoService.shared.invalidateCache()
      await loadMETARs()
      await loadTAFs()
      await loadWindsAloft()
    }
    await loadingTask?.value
    lastLoaded = .now
  }

  public func cancelLoading() {
    loadingTask?.cancel()
    loadingTask = nil
  }

  public func streamConditions(for key: Key) async -> AsyncStream<Loadable<Conditions>> {
    let id = UUID()
    let initialConditions = await conditions(for: key)

    return AsyncStream { continuation in
      conditionsSubscribers[id] = (key, continuation)

      // Send initial value
      continuation.yield(initialConditions)

      continuation.onTermination = { @Sendable _ in
        Task { [weak self] in
          await self?.removeConditionsSubscriber(id: id)
        }
      }
    }
  }

  public func streamMETAR(for key: Key) -> AsyncStream<Loadable<String?>> {
    let id = UUID()
    let initialRaw = observations.map { $0[key.id]?.raw }

    return AsyncStream { continuation in
      metarSubscribers[id] = (key, continuation)

      // Send initial value
      continuation.yield(initialRaw)

      continuation.onTermination = { @Sendable _ in
        Task { [weak self] in
          await self?.removeMetarSubscriber(id: id)
        }
      }
    }
  }

  public func streamTAF(for key: Key) -> AsyncStream<Loadable<String?>> {
    let id = UUID()
    let initialRaw = forecasts.map { $0[key.id]?.raw }

    return AsyncStream { continuation in
      tafSubscribers[id] = (key, continuation)

      // Send initial value
      continuation.yield(initialRaw)

      continuation.onTermination = { @Sendable _ in
        Task { [weak self] in
          await self?.removeTafSubscriber(id: id)
        }
      }
    }
  }

  public func streamWindsAloft(for key: Key) async -> AsyncStream<Loadable<WindsAloftForecast?>> {
    let id = UUID()
    let initialData = await windsAloftForecast(for: key)

    return AsyncStream { continuation in
      windsAloftSubscribers[id] = (key, continuation)

      // Send initial value
      continuation.yield(initialData)

      continuation.onTermination = { @Sendable _ in
        Task { [weak self] in
          await self?.removeWindsAloftSubscriber(id: id)
        }
      }
    }
  }
}
