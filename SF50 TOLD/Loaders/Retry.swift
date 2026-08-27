import Foundation
import Synchronization
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

// periphery:ignore:parameters isolation
/// Downloads a file to disk, reporting the transfer's progress, retrying transient
/// failures, and resuming where a failed attempt left off.
///
/// A download reports its byte counts to the delegate of the session running it and never
/// to one attached to the task, so following a transfer means owning the session for its
/// duration rather than observing a borrowed one. That is why this takes a configuration
/// instead of a session: it builds the session, and invalidates it once the download
/// settles.
///
/// The caller owns the returned file and is responsible for moving or deleting it.
func downloadWithRetry(
  from url: URL,
  configuration: URLSessionConfiguration,
  maximumRetryCount: Int = 3,
  initialDelaySeconds: Int = 2,
  logger: Logger,
  label: String,
  reportingTo progress: AsyncStream<Float>.Continuation? = nil,
  isolation: isolated (any Actor)? = #isolation  // swiftlint:disable:this unused_parameter
) async throws -> (URL, URLResponse) {
  let driver = DownloadDriver(reportingTo: progress)
  let session = URLSession(configuration: configuration, delegate: driver, delegateQueue: nil)
  defer { session.finishTasksAndInvalidate() }

  var resumeData: Data?

  return try await withRetry(
    maximumRetryCount: maximumRetryCount,
    initialDelaySeconds: initialDelaySeconds,
    logger: logger,
    label: label,
    onRetryableFailure: { error in
      resumeData = (error as? URLError)?.userInfo[NSURLSessionDownloadTaskResumeData] as? Data
    },
    operation: { try await driver.download(url, in: session, resumingFrom: resumeData) }
  )
}

/// Drives one download task at a time, bridging a session's delegate callbacks to async.
///
/// The alternative way to follow a download from async code is to iterate
/// `URLSession/bytes(from:)`, whose `AsyncSequence` element is a single byte — following a
/// multi-gigabyte payload that way costs one async resumption per byte, and leaves the
/// caller assembling the payload itself. A delegate reports the same progress while the
/// session writes straight to disk.
private final class DownloadDriver: NSObject, URLSessionDownloadDelegate {
  private let attempt = Mutex(Attempt())
  private let progress: AsyncStream<Float>.Continuation?

  init(reportingTo progress: AsyncStream<Float>.Continuation?) {
    self.progress = progress
    super.init()
  }

  func download(
    _ url: URL,
    in session: URLSession,
    resumingFrom resumeData: Data?
  ) async throws -> (URL, URLResponse) {
    let task =
      resumeData.map(session.downloadTask(withResumeData:))
      ?? session.downloadTask(with: url)

    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { resumption in
        attempt.withLock { $0 = Attempt(resumption: resumption) }
        task.resume()
      }
    } onCancel: {
      task.cancel()
    }
  }

  // MARK: - URLSessionDownloadDelegate

  func urlSession(
    _: URLSession,
    downloadTask _: URLSessionDownloadTask,
    didWriteData _: Int64,
    totalBytesWritten: Int64,
    totalBytesExpectedToWrite: Int64
  ) {
    guard totalBytesExpectedToWrite > 0 else { return }
    progress?.yield(Float(totalBytesWritten) / Float(totalBytesExpectedToWrite))
  }

  /// The session deletes the file it hands over the moment this method returns, so the
  /// payload has to be claimed before that — which rules out doing the move anywhere
  /// asynchronous.
  func urlSession(
    _: URLSession,
    downloadTask _: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL
  ) {
    let destination = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let claimed = Result { try FileManager.default.moveItem(at: location, to: destination) }
      .map { destination }
    attempt.withLock { $0.payload = claimed }
  }

  func urlSession(_: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
    let settled = attempt.withLock { attempt in
      defer { attempt = Attempt() }
      return attempt
    }
    guard let resumption = settled.resumption else { return }

    if let error {
      settled.discardPayload()
      resumption.resume(throwing: error)
      return
    }

    switch (settled.payload, task.response) {
      case (.success(let fileURL), let response?):
        resumption.resume(returning: (fileURL, response))
      case (.failure(let failure), _):
        resumption.resume(throwing: failure)
      default:
        resumption.resume(throwing: URLError(.badServerResponse))
    }
  }

  // MARK: - Nested Types

  /// One download's in-flight state: who is waiting, and what arrived.
  private struct Attempt {
    var resumption: CheckedContinuation<(URL, URLResponse), any Error>?
    var payload: Result<URL, any Error>?

    /// Removes a payload claimed by a transfer that went on to fail, which would otherwise
    /// sit in the temporary directory with nobody left holding its URL.
    func discardPayload() {
      guard case .success(let fileURL) = payload else { return }
      try? FileManager.default.removeItem(at: fileURL)
    }
  }
}
