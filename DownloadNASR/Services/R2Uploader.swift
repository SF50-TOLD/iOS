import Foundation
import Logging
import SwiftR2

/// Errors that can occur during R2 operations.
enum R2Error: LocalizedError {
  case uploadFailed(String, statusCode: Int?)
  case invalidConfig

  var errorDescription: String? {
    String(localized: "Failed to upload to R2 storage.")
  }

  var failureReason: String? {
    switch self {
      case .uploadFailed(let file, let statusCode):
        if let statusCode {
          String(localized: "Upload of “\(file)” failed with HTTP status \(statusCode).")
        } else {
          String(localized: "Upload of “\(file)” failed.")
        }
      case .invalidConfig:
        String(localized: "R2 configuration is missing or invalid.")
    }
  }
}

/// Uploads files to CloudFlare R2 using SwiftR2.
actor R2Uploader {

  // MARK: - Constants

  /// Part size for multipart uploads (10MB).
  private static let partSize = 10 * 1024 * 1024

  // MARK: - Instance Properties

  private let config: Config
  private let logger: Logger
  private let client: R2Client
  private let uploadManager: MultipartUploadManager
  private let byteCountFormatter: ByteCountFormatter = {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    return formatter
  }()

  // MARK: - Initializers

  init(config: Config, logger: Logger) {
    self.config = config
    self.logger = logger

    // Create R2 client with static credentials
    let clientConfig = R2ClientConfiguration(
      accountId: config.accountId,
      accessKeyId: config.accessKeyId,
      secretAccessKey: config.secretAccessKey,
      timeoutInterval: 300  // 5 minute timeout for large uploads
    )

    self.client = R2Client(configuration: clientConfig)

    // Create multipart upload manager with conservative settings
    let uploadConfig = MultipartUploadConfiguration(
      partSize: Self.partSize,
      maxConcurrentUploads: 2,  // Conservative concurrency
      retryFailedParts: true,
      maxRetryAttempts: 3
    )
    self.uploadManager = MultipartUploadManager(client: client, configuration: uploadConfig)
  }

  // MARK: - Methods

  /// Uploads a file to R2 with progress reporting.
  ///
  /// - Parameters:
  ///   - localURL: The local file URL to upload.
  ///   - key: The object key (path) in the R2 bucket.
  ///   - onProgress: Optional callback reporting upload progress (0.0 to 1.0).
  func uploadFile(
    at localURL: URL,
    key: String,
    onProgress: (@Sendable (Double) async -> Void)? = nil
  ) async throws {
    let fileSize =
      try FileManager.default.attributesOfItem(atPath: localURL.path)[.size] as? Int64 ?? 0
    logger.info("Uploading \(key) (\(byteCountFormatter.string(fromByteCount: fileSize))) to R2…")

    do {
      if fileSize <= Self.partSize {
        // Small file: use simple putObject
        logger.debug("Using simple upload for small file")
        let data = try Data(contentsOf: localURL)
        try await client.putObject(
          bucket: config.bucketName,
          key: key,
          body: data,
          contentType: "application/octet-stream"
        )
        await onProgress?(1.0)
      } else {
        // Large file: use multipart upload
        logger.debug(
          "Using multipart upload for \(byteCountFormatter.string(fromByteCount: fileSize)) file"
        )
        _ = try await uploadManager.upload(
          bucket: config.bucketName,
          key: key,
          fileURL: localURL,
          contentType: "application/octet-stream"
        ) { progress in
          if let onProgress, let total = progress.totalBytes, total > 0 {
            let fraction = Double(progress.completedBytes) / Double(total)
            Task { await onProgress(min(1.0, fraction)) }
          }
        }
      }
      logger.notice("Uploaded \(key) to R2")
    } catch {
      logger.error("R2 upload failed: \(error)")
      throw R2Error.uploadFailed(localURL.lastPathComponent, statusCode: nil)
    }
  }

  // MARK: - Nested Types

  /// Configuration for R2 uploads.
  struct Config: Sendable {
    private static let endpointTemplate = "https://%@.r2.cloudflarestorage.com"

    let accountId: String
    let accessKeyId: String
    let secretAccessKey: String
    let bucketName: String
    let publicURL: String

    /// S3-compatible endpoint URL for R2.
    var endpoint: String {
      String(format: Self.endpointTemplate, accountId)
    }

    /// Load from Bundle (Info.plist values from xcconfig).
    static func fromBundle() -> Self? {
      guard let accountId = CredentialsConfig[.r2AccountID],
        let accessKey = CredentialsConfig[.r2AccessKeyID],
        let secretKey = CredentialsConfig[.r2SecretAccessKey],
        let bucket = CredentialsConfig[.r2BucketName],
        let publicURL = CredentialsConfig[.r2PublicURL]
      else { return nil }
      return Self(
        accountId: accountId,
        accessKeyId: accessKey,
        secretAccessKey: secretKey,
        bucketName: bucket,
        publicURL: publicURL
      )
    }
  }
}
