import Foundation
import os

// periphery:ignore:parameters isolation
/// Retries an async operation with exponential backoff.
///
/// `CancellationError` and `URLError.cancelled` always rethrow immediately.
/// Other errors are tested with `shouldRetry`; transient errors are retried
/// up to `maximumRetryCount` additional times with exponential backoff
/// starting at `initialDelaySeconds`.
func withRetry<T>(
  maximumRetryCount: Int = 3,
  initialDelaySeconds: Int = 2,
  logger: Logger,
  label: String,
  shouldRetry: (any Error) -> Bool = { $0 is URLError },
  onRetryableFailure: (any Error) -> Void = { _ in },
  isolation: isolated (any Actor)? = #isolation,  // swiftlint:disable:this unused_parameter
  operation: () async throws -> T
) async throws -> T {
  for attempt in 0...maximumRetryCount {
    if attempt > 0 {
      let delaySeconds = initialDelaySeconds * (1 << (attempt - 1))
      logger.info(
        "\(label): retrying (attempt \(attempt + 1)/\(maximumRetryCount + 1), delay: \(delaySeconds)s)"
      )
      try await Task.sleep(for: .seconds(delaySeconds))
    }

    do {
      return try await operation()
    } catch {
      if error is CancellationError { throw error }
      if let urlError = error as? URLError, urlError.code == .cancelled { throw urlError }
      if !shouldRetry(error) { throw error }
      onRetryableFailure(error)
      if attempt == maximumRetryCount { throw error }
    }
  }

  fatalError("Retry loop exited without returning or throwing")
}

extension URLSession {

  // periphery:ignore:parameters isolation
  /// Downloads a file with automatic retry and resume-data support.
  ///
  /// On transient `URLError` failures the method retries with exponential
  /// backoff. When the server supplies resume data the next attempt continues
  /// where the previous one left off.
  func downloadWithRetry(
    from url: URL,
    maximumRetryCount: Int = 3,
    initialDelaySeconds: Int = 2,
    logger: Logger,
    label: String,
    delegate: (any URLSessionTaskDelegate)? = nil,
    isolation: isolated (any Actor)? = #isolation  // swiftlint:disable:this unused_parameter
  ) async throws -> (URL, URLResponse) {
    var resumeData: Data?

    return try await withRetry(
      maximumRetryCount: maximumRetryCount,
      initialDelaySeconds: initialDelaySeconds,
      logger: logger,
      label: label,
      onRetryableFailure: { error in
        if let urlError = error as? URLError {
          resumeData = urlError.userInfo[NSURLSessionDownloadTaskResumeData] as? Data
        }
      },
      operation: {
        if let resumeData {
          return try await self.download(resumeFrom: resumeData, delegate: delegate)
        }
        return try await self.download(from: url, delegate: delegate)
      }
    )
  }
}

/// Reports a download task's completion fraction into an `AsyncStream`.
///
/// The alternative way to follow a download from async code is to iterate
/// `URLSession/bytes(from:)`, whose `AsyncSequence` element is a single byte —
/// following a multi-megabyte payload that way costs one async resumption per
/// byte, and leaves the caller assembling the payload itself. A download
/// delegate reports the same progress while the session writes straight to
/// disk.
final class DownloadProgressObserver: NSObject, URLSessionDownloadDelegate {
  private let continuation: AsyncStream<Float>.Continuation

  init(reportingTo continuation: AsyncStream<Float>.Continuation) {
    self.continuation = continuation
  }

  func urlSession(
    _: URLSession,
    downloadTask _: URLSessionDownloadTask,
    didWriteData _: Int64,
    totalBytesWritten: Int64,
    totalBytesExpectedToWrite: Int64
  ) {
    guard totalBytesExpectedToWrite > 0 else { return }
    continuation.yield(Float(totalBytesWritten) / Float(totalBytesExpectedToWrite))
  }

  /// Required by `URLSessionDownloadDelegate`, but the async download API hands
  /// the finished file back to its caller, so there is nothing to do here.
  func urlSession(
    _: URLSession,
    downloadTask _: URLSessionDownloadTask,
    didFinishDownloadingTo _: URL
  ) {}
}
