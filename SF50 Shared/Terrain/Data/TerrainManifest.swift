import Foundation

/// Parsed terrain manifest from the bundled JSON file.
///
/// The manifest contains metadata about available terrain regions including
/// their actual file sizes. This is used to display accurate download sizes
/// in the UI rather than hardcoded estimates.
public struct TerrainManifest: Decodable, Sendable {

  // MARK: - Type Properties

  /// The bundled terrain manifest, loaded once at app startup.
  public static let bundled: Self = {
    guard let url = Bundle.main.url(forResource: "terrain-manifest", withExtension: "json") else {
      fatalError("terrain-manifest.json missing from bundle")
    }

    do {
      let data = try Data(contentsOf: url)
      let decoder = JSONDecoder()
      decoder.dateDecodingStrategy = .iso8601
      return try decoder.decode(Self.self, from: data)
    } catch {
      fatalError("Failed to decode terrain-manifest.json: \(error)")
    }
  }()

  public static let defaultBaseURL = URL(
    string: "https://pub-becd30c7b4e24860bee04cbbab788fb3.r2.dev/terrain/"
  )!

  /// Manifest layout this build understands, in which each region is a raw `.srtm` payload.
  public static let currentVersion = 3

  /// Where the manifest for ``currentVersion`` is published.
  ///
  /// Each layout is published at its own URL, so a build reads the manifest it was compiled against
  /// and finds payloads in the form it expects.
  public static let defaultManifestURL = URL(
    string: defaultBaseURL.absoluteString + "terrain-manifest-v3.json"
  )!

  // MARK: - Instance Properties

  public let baseURL: String
  public let generatedAt: Date
  public let version: Int
  public let regions: [Region]

  /// Returns the effective base URL for downloads.
  public var effectiveBaseURL: String {
    if !baseURL.isEmpty {
      return baseURL.hasSuffix("/") ? baseURL : baseURL + "/"
    }
    return Self.defaultBaseURL.absoluteString
  }

  // MARK: - Instance Methods

  /// Returns the manifest region for the given region ID.
  public func region(forID regionID: String) -> Region? {
    regions.first { $0.id == regionID }
  }

  // MARK: - Nested Types

  /// A single region entry in the manifest.
  public struct Region: Decodable, Sendable {
    public let filename: String
    public let id: String
    public let sizeBytes: Int
  }
}
