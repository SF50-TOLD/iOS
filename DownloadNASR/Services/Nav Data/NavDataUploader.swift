import Foundation
import Logging
import SwiftNASR

/// Uploads a generated nav-data file to the legacy Airport-Data GitHub repository.
///
/// Keeps already-installed app versions fed during the NavDataDistribution
/// transition. Uploading is best-effort: a failure is reported to the caller but
/// never fails the surrounding generation.
struct NavDataUploader {
  /// The cycle whose data is being uploaded.
  let cycle: Cycle

  /// Logger for status messages and errors.
  let logger: Logger

  /// Uploads the file to GitHub, if a token is configured.
  /// - Parameter file: The `<cycle>.plist.lzma` file to upload.
  /// - Returns: The error if the upload failed, or `nil` on success or when no token is configured.
  func upload(file: URL) async -> NSError? {
    guard CredentialsConfig[.githubToken] != nil else {
      logger.info("GitHub token not configured, skipping upload")
      return nil
    }

    logger.notice("Uploading to GitHub…")
    do {
      let uploader = GitHubUploader(logger: logger)
      try await uploader.uploadFile(
        filePath: file,
        targetPath: "3.0/\(cycle).plist.lzma",
        commitMessage: "Update airport and obstacle data for cycle \(cycle)"
      )
      logger.notice("Successfully uploaded data to GitHub")
      return nil
    } catch {
      logger.warning("GitHub upload failed: \(error.localizedDescription)")
      return error as NSError
    }
  }
}
