public import CoreLocation
import Sentry
public import SwiftUI

/// Whether Core Location is delivering the device’s location, and if not, why.
///
/// Core Location reports these conditions as diagnostic flags on every
/// `CLLocationUpdate`, so a refusal arrives on the same stream as a fix rather
/// than through a separate authorization callback.
public enum LocationAvailability: Sendable {
  /// The system is asking for authorization and has not yet received an answer.
  case requestingAuthorization

  /// A location is available.
  case available

  /// This app was denied access to location.
  case authorizationDenied

  /// Location Services is turned off for the whole device.
  case authorizationDeniedGlobally

  /// Authorization is prevented by parental restrictions or device management.
  case authorizationRestricted

  /// The device’s location can’t be determined right now.
  ///
  /// Covers both a location Core Location cannot fix and updates it is
  /// withholding because the app is not sufficiently in use. Neither is
  /// actionable, and the distinction is not one a person can act on.
  case locationUnavailable

  /// Whether this is a refusal a person could lift, in Settings or otherwise.
  ///
  /// Drives the retry that runs when someone grants access and returns to the app.
  public var deniesAuthorization: Bool {
    switch self {
      case .authorizationDenied, .authorizationDeniedGlobally, .authorizationRestricted: true
      case .requestingAuthorization, .available, .locationUnavailable: false
    }
  }

  /// Reads the refusal an update reports, or `nil` if Core Location is not refusing.
  ///
  /// - Parameter update: The update whose diagnostic flags to interpret.
  init?(refusing update: CLLocationUpdate) {
    if update.authorizationRequestInProgress {
      self = .requestingAuthorization
    } else if update.authorizationDeniedGlobally {
      self = .authorizationDeniedGlobally
    } else if update.authorizationDenied {
      self = .authorizationDenied
    } else if update.authorizationRestricted {
      self = .authorizationRestricted
    } else if update.locationUnavailable || update.insufficientlyInUse {
      self = .locationUnavailable
    } else {
      return nil
    }
  }
}

/// Protocol for streaming device location updates.
///
/// ``LocationStreamer`` provides an abstraction for accessing device location,
/// allowing dependency injection of mock locations for testing.
///
/// Conformers are reference types so that SwiftUI observes their state in place;
/// a value type would be copied into the existential and its changes never seen.
@MainActor
public protocol LocationStreamer: AnyObject, Observable, Sendable {
  /// The most recent location, or nil if unavailable.
  var location: CLLocation? { get }
  /// Any error that occurred during location updates.
  var error: (any Error)? { get }
  /// Whether a location is available, and if not, why — or nil before the first update arrives.
  var availability: LocationAvailability? { get }

  /// Start receiving location updates.
  func start() async
  /// Stop receiving location updates.
  func stop() async
  /// Ask Core Location again after a refusal, without disturbing existing subscribers.
  func retry() async
  /// Returns an async stream of location updates.
  func locationUpdates() -> AsyncStream<CLLocation>
}

/// Core Location-based implementation of ``LocationStreamer``.
///
/// ``CoreLocationStreamer`` wraps `CLLocationUpdate.liveUpdates()` to provide:
/// - Reference-counted start/stop
/// - Async stream of location updates
/// - Authorization state read from the update stream’s own diagnostics
///
/// ## Authorization
///
/// Core Location requests authorization when iteration over the update stream
/// begins, and reports the outcome — including a request still in flight, a
/// denial, or a device-wide switch-off — as flags on the updates themselves. So
/// this type asks for nothing up front and polls nothing; it reads
/// ``availability`` off the stream.
///
/// ## Reference Counting
///
/// Multiple callers can call ``start()`` independently, and each subscriber to
/// ``locationUpdates()`` counts as one. Location updates only stop once every
/// caller has balanced its ``start()`` with a ``stop()`` and every subscription
/// has ended.
///
/// ## SwiftUI Integration
///
/// The streamer is available via the SwiftUI environment:
///
/// ```swift
/// @Environment(\.locationStreamer) var locationStreamer
/// ```
@MainActor
@Observable
public final class CoreLocationStreamer: LocationStreamer {
  public private(set) var location: CLLocation?
  public private(set) var error: (any Error)?
  public private(set) var availability: LocationAvailability?

  private var updateTask: Task<Void, Never>?
  private var listenerCount = 0
  private var continuationMap = [UUID: AsyncStream<CLLocation>.Continuation]()

  /// Identifies the current stream, so a finishing one cannot disown its replacement.
  private var streamGeneration = 0

  public init() {}

  public func start() {
    listenerCount += 1
    if listenerCount == 1 { _start() }
  }

  public func stop() {
    // A release can arrive before its acquire: a view that appears and disappears
    // within one runloop turn has its `task` cancelled before it ever starts. Counting
    // that release would leave the tally below zero, where `start()` can never bring it
    // back to one — and the stream would never run again.
    guard listenerCount > 0 else { return }
    listenerCount -= 1
    if listenerCount == 0 { _stop() }
  }

  /// Restarts the update stream after a refusal.
  ///
  /// Someone who grants access in Settings and comes back gets their list without
  /// leaving the screen. Subscribers are left connected, so this is not a ``stop()``
  /// followed by a ``start()``.
  public func retry() {
    guard listenerCount > 0 else { return }
    updateTask?.cancel()
    updateTask = nil
    clearStreamDiagnostics()
    _start()
  }

  public func locationUpdates() -> AsyncStream<CLLocation> {
    let id = UUID()

    return AsyncStream { continuation in
      // The handler has to be in place before the stream reaches its consumer. A consumer
      // whose task is already cancelled terminates the stream on its first `await`, and a
      // handler installed after that point is never called — leaving the listener this
      // subscription adds with nothing to ever take it away.
      continuation.onTermination = { _ in
        Task { @MainActor in self.endSubscription(id) }
      }

      continuationMap[id] = continuation
      if let location { continuation.yield(location) }
      start()
    }
  }

  /// Releases the listener a subscription holds, once and only once.
  private func endSubscription(_ id: UUID) {
    // `_stop()` clears the map before finishing continuations, so a termination it
    // caused must not decrement the count a second time.
    guard continuationMap.removeValue(forKey: id) != nil else { return }
    stop()
  }

  private func _start() {
    guard updateTask == nil else { return }

    streamGeneration += 1
    let generation = streamGeneration

    updateTask = Task {
      // Only clear the handle if this is still the live stream: ``retry()`` may
      // already have replaced it, and nilling it then would strand a running task.
      defer { if generation == streamGeneration { updateTask = nil } }
      do {
        for try await update in CLLocationUpdate.liveUpdates(.airborne) {
          if Task.isCancelled { break }
          apply(update)
        }
      } catch {
        // ``_stop()`` and ``retry()`` both cancel this task, and the stream may report that
        // by throwing rather than by ending. That is this app taking the stream down, not a
        // failure to show anyone or to log.
        guard !Task.isCancelled, !(error is CancellationError) else { return }
        SentrySDK.capture(error: error) { scope in
          scope.setFingerprint(["location", "streaming"])
        }
        self.error = error
      }
    }
  }

  private func _stop() {
    updateTask?.cancel()
    updateTask = nil
    clearStreamDiagnostics()

    let continuations = continuationMap.values
    continuationMap.removeAll()
    for continuation in continuations { continuation.finish() }
  }

  /// Forgets what the update stream reported, so a refusal or a failure cannot outlive it.
  ///
  /// Nothing else clears ``error``. A fix arriving is the only other thing that does, and a
  /// stream that has stopped, or that is being retried, delivers none until it runs again —
  /// so a single failure would otherwise stand for as long as this object does.
  private func clearStreamDiagnostics() {
    availability = nil
    error = nil
  }

  private func apply(_ update: CLLocationUpdate) {
    if let refusal = LocationAvailability(refusing: update) {
      availability = refusal
      return
    }

    // No refusal and no fix yet: Core Location is still acquiring one.
    guard let newLocation = update.location else { return }

    availability = .available
    location = newLocation
    error = nil
    for continuation in continuationMap.values { continuation.yield(newLocation) }
  }
}

private struct LocationStreamerKey: EnvironmentKey {
  static let defaultValue: any LocationStreamer = {
    MainActor.assumeIsolated {
      CoreLocationStreamer()
    }
  }()
}

extension EnvironmentValues {
  public var locationStreamer: any LocationStreamer {
    get { self[LocationStreamerKey.self] }
    set { self[LocationStreamerKey.self] = newValue }
  }
}
