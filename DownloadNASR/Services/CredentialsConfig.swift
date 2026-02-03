import Foundation

/// Validates and provides access to credentials from Info.plist (via xcconfig).
enum CredentialsConfig {

  // MARK: - Type Methods

  /// Required credentials that must be present for the app to run.
  static func validateRequired() -> [String] {
    Key.allCases.filter { self[$0] == nil }.map(\.rawValue)
  }

  // MARK: - Subscripts

  static subscript(key: Key) -> String? {
    guard let value = Bundle.main.object(forInfoDictionaryKey: key.rawValue) as? String,
      !value.isEmpty,
      !value.hasPrefix("$(")  // Not substituted
    else { return nil }
    return value
  }

  // MARK: - Subtypes

  enum Key: String, CaseIterable {
    case r2AccountID = "R2_ACCOUNT_ID"
    case r2AccessKeyID = "R2_ACCESS_KEY_ID"
    case r2SecretAccessKey = "R2_SECRET_ACCESS_KEY"
    case r2BucketName = "R2_BUCKET_NAME"
    case r2PublicURL = "R2_PUBLIC_URL"
    case githubToken = "GITHUB_TOKEN"
  }
}
