import CoreLocation
import Foundation
import Logging
import NavData

/// The seam a ``PathAtmosphere`` is fetched through.
///
/// Lets a UI test stand in for the network, so a test that switches weather layers doesn't depend
/// on reaching a forecast service.
public protocol PathAtmosphereLoading: Actor {
  /// The atmosphere along a path at a time.
  ///
  /// - Parameters:
  ///   - points: The path, ordered from its origin.
  ///   - time: The time the weather is needed for.
  /// - Returns: The sampled atmosphere.
  /// - Throws: ``PathAtmosphereLoader/Failure`` if it couldn't be fetched.
  func atmosphere(
    along points: [PathAtmosphereLoader.PathPoint],
    at time: Date
  ) async throws -> PathAtmosphere
}

/**
 * Actor that samples the atmosphere along a flight path.
 *
 * A forecast column describes the air for some way around itself, so most paths are covered by the
 * one column standing over the airport. A path that runs beyond that reach — a procedure climbing
 * to a high top altitude can run tens of miles downrange — is sampled again, sparsely, until it is
 * covered.
 *
 * ## Caching
 *
 * A climb profile recomputes whenever any of its inputs change, and its weather does not: the same
 * columns and the same forecast hour give the same answer for as long as the forecast behind them
 * stands. One result is held per path and hour until the weather behind it is refreshed, and
 * concurrent requests for the same path await one fetch.
 */
public actor PathAtmosphereLoader: PathAtmosphereLoading {

  /// Shared singleton instance for app-wide path weather access.
  public static let shared = PathAtmosphereLoader()

  /// How far from a column its forecast is taken to describe the air, in nautical miles.
  ///
  /// A TAF is issued for the five miles around its airport, and that is about the distance over
  /// which one report can honestly stand in for the weather. A path staying inside it needs a single
  /// column.
  public static let columnRadiusNM: Double = 5

  /// The most columns one path is sampled with.
  ///
  /// A max-gross enroute climb to the highest top altitude a procedure asks for runs on the order of
  /// a hundred miles, which is about two dozen columns at ``columnRadiusNM``. Beyond that the path
  /// is left uncovered rather than sampled more coarsely, and ``PathAtmosphere/isTruncated`` says so.
  public static let maxColumns = 24

  private static let logger = Logger(label: "codes.tim.SF50-TOLD.PathAtmosphereLoader")

  private var cache = [CacheKey: CachedAtmosphere]()

  private var fetches = [CacheKey: Task<PathAtmosphere, any Error>]()

  private var failures = [CacheKey: CachedFailure]()

  /// When a refusal for want of a connection stops standing.
  ///
  /// Being offline is a property of the device, not of the path asked for, so one refusal answers
  /// for every path until it goes stale. Without this, changing the departure or the go-around type
  /// would each earn their own wait for a request that cannot succeed.
  private var offlineUntil: Date?

  private init() {}

  /// Chooses the points along a path to sample the atmosphere at.
  ///
  /// Walks the path from its origin, taking a column wherever the path has left every column already
  /// taken behind by more than ``columnRadiusNM``. A path that never leaves the first column's reach
  /// yields exactly one.
  ///
  /// - Parameter points: The path, ordered from its origin.
  /// - Returns: Indices into `points` to sample at, and whether ``maxColumns`` cut the walk short.
  static func columnIndices(
    along points: [PathPoint]
  ) -> (indices: [Int], truncated: Bool) {
    guard !points.isEmpty else { return ([], false) }

    var indices = [0]
    for (index, point) in points.enumerated().dropFirst() {
      let covered = indices.contains { chosen in
        GeoCalculations.distanceNM(from: points[chosen].coordinate, to: point.coordinate)
          <= columnRadiusNM
      }
      if covered { continue }
      guard indices.count < maxColumns else { return (indices, true) }
      indices.append(index)
    }
    return (indices, false)
  }

  private static func load(
    _ points: [PathPoint],
    at time: Date,
    truncated: Bool
  ) async throws -> PathAtmosphere {
    let profiles = try await OpenMeteoService.shared.profiles(
      at: points.map(\.coordinate),
      for: time
    )

    let columns = zip(points, profiles).compactMap { point, profile in
      profile.map { PathAtmosphere.Column(distanceNM: point.distanceNM, profile: $0) }
    }

    return .init(
      columns: columns,
      providers: columns.isEmpty ? [] : .openMeteo,
      isTruncated: truncated
    )
  }

  /// The atmosphere along a path at a time.
  ///
  /// - Parameters:
  ///   - points: The path, ordered from its origin.
  ///   - time: The time the weather is needed for.
  /// - Returns: The sampled atmosphere, empty if no column reported anything.
  /// - Throws: ``Failure`` if the forecast couldn't be fetched.
  public func atmosphere(along points: [PathPoint], at time: Date) async throws -> PathAtmosphere {
    let (indices, truncated) = Self.columnIndices(along: points)
    guard !indices.isEmpty else { return .init(columns: [], providers: []) }

    if truncated {
      Self.logger.notice(
        "Path exceeds the column limit; weather layers stop short of its end",
        metadata: ["columns": "\(indices.count)", "points": "\(points.count)"]
      )
    }

    let sampled = indices.map { points[$0] }
    // The request is bounded to the hours around `time` and read from the one covering it, so every
    // time inside an hour has the same answer, and one held result serves them all.
    let key = CacheKey(points: sampled, hour: time.startOfHour)

    if let cached = cache[key], cached.isFresh { return cached.atmosphere }
    // A remembered refusal is answered straight away rather than by another doomed request.
    if let offlineUntil, offlineUntil > .now { throw Failure.offline }
    if let failed = failures[key], failed.isFresh { throw failed.failure }
    if let fetch = fetches[key] { return try await result(of: fetch, for: key) }

    let fetch = Task { try await Self.load(sampled, at: time, truncated: truncated) }
    fetches[key] = fetch
    defer { fetches[key] = nil }

    return try await result(of: fetch, for: key)
  }

  /// Awaits a fetch, holding on to whatever it answers with.
  ///
  /// Every caller of one fetch goes through here, including those that joined it already in flight,
  /// so all of them are answered with a ``Failure`` and one refusal is remembered once however many
  /// were waiting on it.
  private func result(
    of fetch: Task<PathAtmosphere, any Error>,
    for key: CacheKey
  ) async throws -> PathAtmosphere {
    do {
      let atmosphere = try await fetch.value
      cache[key] = .init(atmosphere: atmosphere, fetchedAt: .now)
      failures[key] = nil
      offlineUntil = nil
      return atmosphere
    } catch {
      let failure = Failure(error)
      switch failure {
        case .offline: offlineUntil = .now.addingTimeInterval(WeatherLoader.reloadInterval)
        case .unavailable: failures[key] = .init(failure: failure, fetchedAt: .now)
      }
      throw failure
    }
  }

  /// Discards cached atmospheres, so the next request fetches afresh.
  public func invalidateCache() {
    cache.removeAll()
    failures.removeAll()
    offlineUntil = nil
  }

  /// A point on a path the atmosphere can be sampled at.
  public struct PathPoint: Sendable, Hashable {

    /// The geographic point.
    public let latitude: Double, longitude: Double

    /// Distance from the path's origin, in nautical miles.
    public let distanceNM: Double

    /// The geographic point.
    public var coordinate: CLLocationCoordinate2D {
      .init(latitude: latitude, longitude: longitude)
    }

    /// Creates a path point.
    ///
    /// - Parameters:
    ///   - coordinate: The geographic point.
    ///   - distanceNM: Distance from the path's origin, in nautical miles.
    public init(coordinate: CLLocationCoordinate2D, distanceNM: Double) {
      latitude = coordinate.latitude
      longitude = coordinate.longitude
      self.distanceNM = distanceNM
    }
  }

  /// Why an atmosphere couldn't be fetched.
  public enum Failure: Error, Equatable, Sendable {

    /// The forecast service couldn't be reached at all.
    ///
    /// The case a go-around profile is most often planned in: in the air, with no connection.
    case offline

    /// The service was reached but couldn't answer.
    case unavailable

    /// Classifies why a fetch failed.
    ///
    /// - Parameter error: The error the fetch threw.
    public init(_ error: any Error) {
      if let failure = error as? Failure {
        self = failure
      } else {
        self = WeatherLoader.isTransientNetworkError(error) ? .offline : .unavailable
      }
    }
  }

  /// A refusal held until it goes stale, so it isn't re-earned on every recomputation.
  private struct CachedFailure: Sendable {
    let failure: Failure
    let fetchedAt: Date

    var isFresh: Bool { fetchedAt.timeIntervalSinceNow > -WeatherLoader.reloadInterval }
  }

  /// Identifies a request by the columns it samples and the hour it asks for.
  private struct CacheKey: Hashable {
    let points: [PathPoint]
    let hour: Date
  }

  /// An atmosphere held until it goes stale.
  private struct CachedAtmosphere: Sendable {
    let atmosphere: PathAtmosphere
    let fetchedAt: Date

    var isFresh: Bool { fetchedAt.timeIntervalSinceNow > -WeatherLoader.reloadInterval }
  }
}
