/// A type representing the loading state of asynchronous data.
///
/// ``Loadable`` provides a four-state enum for tracking async operation status:
/// - ``notLoaded``: Initial state, no load attempted
/// - ``loading``: Load in progress
/// - ``value(_:)``: Successfully loaded with data
/// - ``error(_:)``: Load failed with error
///
/// ## Usage
///
/// Use `Loadable` for data that may not be immediately available:
///
/// ```swift
/// @Published var weather: Loadable<Conditions> = .notLoaded
///
/// func loadWeather() async {
///     weather = .loading
///     do {
///         let data = try await fetchWeather()
///         weather = .value(data)
///     } catch {
///         weather = .error(error)
///     }
/// }
/// ```
///
/// ## Transforming Values
///
/// The ``map(_:)`` method transforms loaded values while preserving state:
///
/// ```swift
/// let temperatures: Loadable<[Temperature]> = conditions.map { $0.temperature }
/// ```
public enum Loadable<Loaded>: Sendable where Loaded: Sendable {
  /// Initial state before any load attempt.
  case notLoaded
  /// Load operation is in progress.
  case loading
  /// Successfully loaded with the given value.
  case value(_ value: Loaded)
  /// Load failed with the given error.
  case error(_ error: any Error)

  /// Transforms the loaded value using the given closure.
  /// - Parameter transform: A closure that transforms the loaded value.
  /// - Returns: A new `Loadable` with the transformed value, or the same state if not loaded.
  public func map<U>(_ transform: (Loaded) throws -> U) rethrows -> Loadable<U> {
    switch self {
      case .value(let value):
        .value(try transform(value))
      case .error(let error): .error(error)
      case .loading: .loading
      case .notLoaded: .notLoaded
    }
  }
}

extension Loadable {
  /// Whether data has been successfully loaded.
  public var hasValue: Bool {
    if case .value = self { return true }
    return false
  }
}
