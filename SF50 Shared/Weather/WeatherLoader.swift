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
  /// - Parameter key: Identifies the airport to monitor.
  /// - Returns: Async stream yielding winds aloft data as it becomes available.
  ///   Returns `nil` for airports without a winds aloft reporting station.
  func streamWindsAloft(for key: WeatherLoader.Key) async -> AsyncStream<Loadable<WindsAloftData?>>

  /// Returns interpolated winds aloft for a specific location and altitude.
  ///
  /// This method performs spatial interpolation from nearby winds aloft stations
  /// when no direct station match exists for the location.
  ///
  /// - Parameters:
  ///   - coordinate: The target location
  ///   - altitude: The target altitude
  /// - Returns: Interpolated winds aloft entry, or `nil` if insufficient data
  func interpolatedWindsAloft(
    at coordinate: CLLocationCoordinate2D,
    altitude: Measurement<UnitLength>
  ) async -> WindsAloftData.Entry?
}

/**
 * Actor responsible for loading and caching weather data from multiple sources.
 *
 * ``WeatherLoader`` downloads METAR observations and TAF forecasts from Aviation Weather
 * (aviationweather.gov) and supplements them with Apple WeatherKit data. It provides
 * reactive streams of weather conditions that update when new data is loaded.
 *
 * ## Data Sources
 *
 * Weather data is combined from:
 * - **Aviation Weather**: METAR observations and TAF forecasts (primary source for airports)
 * - **WeatherKit**: Current conditions and hourly forecasts (fills gaps in aviation data)
 *
 * ## Time-Based Conditions
 *
 * The loader automatically selects the appropriate data source based on time:
 * - **Current** (within 1 hour): Uses METAR observation, augmented with WeatherKit
 * - **Future**: Uses TAF forecast period covering the requested time
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

  static let reloadInterval = 60.0 * 15
  static let METARsURL = URL(
    string: "https://aviationweather.gov/data/cache/metars.cache.xml.gz"
  )!
  static let TAFsURL = URL(
    string: "https://aviationweather.gov/data/cache/tafs.cache.xml.gz"
  )!
  static let windsAloftURL = URL(
    string: "https://aviationweather.gov/api/data/windtemp?level=low&fcst=06&region=all&layout=on"
  )!
  static let logger = Logger(label: "codes.tim.SF50-TOLD.WeatherLoader")
  static let weatherService = WeatherService()

  var observations: Loadable<[String: Observation]> = .notLoaded {
    didSet { Task { await notifySubscribers() } }
  }
  var forecasts: Loadable<[String: Forecast]> = .notLoaded {
    didSet { Task { await notifySubscribers() } }
  }
  var windsAloft: Loadable<[String: WindsAloftData]> = .notLoaded {
    didSet { Task { await notifySubscribers() } }
  }
  var stationLocations: [String: CLLocationCoordinate2D] = [:]
  var lastLoaded: Date?
  var conditionsSubscribers = [
    UUID: (Key, AsyncStream<Loadable<Conditions>>.Continuation)
  ]()
  var metarSubscribers = [UUID: (Key, AsyncStream<Loadable<String?>>.Continuation)]()
  var tafSubscribers = [UUID: (Key, AsyncStream<Loadable<String?>>.Continuation)]()
  var windsAloftSubscribers = [
    UUID: (Key, AsyncStream<Loadable<WindsAloftData?>>.Continuation)
  ]()
  var loadingTask: Task<Void, Never>?

  var session: URLSession { .init(configuration: .ephemeral) }

  private init() {}

  public func load(force: Bool = false) async {
    if !force, let lastLoaded, lastLoaded.timeIntervalSinceNow > -Self.reloadInterval {
      return
    }
    loadingTask?.cancel()
    loadingTask = Task {
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

  public func streamWindsAloft(for key: Key) -> AsyncStream<Loadable<WindsAloftData?>> {
    let id = UUID()
    let initialData = windsAloftData(for: key)

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

  public func interpolatedWindsAloft(
    at coordinate: CLLocationCoordinate2D,
    altitude: Measurement<UnitLength>
  ) -> WindsAloftData.Entry? {
    guard case .value(let stationData) = windsAloft else { return nil }

    // Build located stations from available data
    let locatedStations: [WindsAloftInterpolator.LocatedStation] = stationData.compactMap {
      stationID,
      data in
      guard let location = stationLocations[stationID] else { return nil }
      return WindsAloftInterpolator.LocatedStation(
        stationID: stationID,
        coordinate: location,
        data: data
      )
    }

    return WindsAloftInterpolator.interpolate(
      at: coordinate,
      altitude: altitude,
      from: locatedStations
    )
  }

  /// Resolves station locations from the airport database.
  ///
  /// Call this after loading winds aloft data to enable spatial interpolation.
  /// Station IDs are matched against airport location IDs.
  ///
  /// - Parameter locations: Dictionary mapping location IDs to coordinates.
  public func setStationLocations(_ locations: [String: CLLocationCoordinate2D]) {
    stationLocations = locations
  }
}
