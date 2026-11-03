import Foundation

private let transientURLErrorCodes: Set<URLError.Code> = [
  .cancelled,
  .cannotFindHost,
  .notConnectedToInternet,
  .networkConnectionLost,
  .timedOut,
  .dnsLookupFailed,
  .cannotConnectToHost,
  .internationalRoamingOff,
  .dataNotAllowed,
  .secureConnectionFailed
]

extension Error {
  /// Whether this error is a task or URL load that was cancelled, rather than one that failed.
  public var isNetworkCancellation: Bool {
    if self is CancellationError { return true }
    if let urlError = self as? URLError, urlError.code == .cancelled { return true }
    return false
  }

  /// Whether this error comes from the device's network conditions, such as having no coverage or
  /// a connection dropping, rather than from the server or this app.
  public var isTransientNetworkError: Bool {
    guard let urlError = self as? URLError else { return false }
    return transientURLErrorCodes.contains(urlError.code)
  }
}
