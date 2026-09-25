import BackgroundAssets
import Defaults
import Foundation
import SF50_Shared
import System

/// Checks a terrain asset pack's payload against the SHA-256 the pack carries beside it.
///
/// Background Assets verifies nothing about a pack's contents, so a payload damaged in transit or
/// on disk would otherwise be read as terrain. Each pack published since the sidecar was added
/// carries its payload's digest, which describes exactly the version installed.
///
/// Hashing a payload of several gigabytes takes seconds, so each verdict is kept against the
/// payload file's identity and reused until the file changes, which it does whenever the system
/// installs a new version of the pack.
struct TerrainPayloadVerifier: Sendable {

  // MARK: - Instance Properties

  /// The digest `region`'s installed pack carries, or `nil` for a pack published without one.
  private let expectedDigest: @Sendable (TerrainRegion) -> String?

  /// Reads and records verdicts, so each version of a payload is hashed once.
  private let verdicts: VerdictStore

  // MARK: - Initializers

  init(expectedDigest: @escaping @Sendable (TerrainRegion) -> String?, verdicts: VerdictStore) {
    self.expectedDigest = expectedDigest
    self.verdicts = verdicts
  }

  /// Reads digests from the system's asset-pack store, and keeps verdicts in the app's defaults.
  init() {
    self.init(expectedDigest: Self.installedPackDigest, verdicts: .defaults)
  }

  // MARK: - Type Methods

  /// The digest in `region`'s installed pack, or `nil` if the pack carries none.
  private static func installedPackDigest(for region: TerrainRegion) -> String? {
    guard
      let data = try? AssetPackManager.shared.contents(
        at: FilePath(region.digestFilename),
        searchingInAssetPackWithID: region.downloadIdentifier
      )
    else { return nil }
    return String(bytes: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  // MARK: - Instance Methods

  /// Whether the payload at `payloadURL` is the one `region`'s pack describes.
  ///
  /// - Throws: If the payload cannot be read, which says nothing about whether it is intact.
  func verdict(for region: TerrainRegion, payloadAt payloadURL: URL) throws -> Verdict {
    let fingerprint = try Fingerprint(of: payloadURL)
    if let recorded = verdicts.read(region), recorded.fingerprint == fingerprint {
      return recorded.verdict
    }

    let verdict: Verdict
    if let expected = expectedDigest(region) {
      let actual = try TerrainPayloadDigest.hexDigest(ofFileAt: payloadURL)
      verdict = actual == expected.lowercased() ? .intact : .damaged
    } else {
      verdict = .unverifiable
    }

    verdicts.write(region, Record(fingerprint: fingerprint, verdict: verdict))
    return verdict
  }

  // MARK: - Nested Types

  /// What checking a payload found.
  enum Verdict: String, Codable, Sendable {
    /// The payload's digest matches the one its pack carries.
    case intact
    /// The payload's digest differs from the one its pack carries.
    case damaged
    /// The pack carries no digest to check against, as packs published before the sidecar don't.
    case unverifiable
  }

  /// Identifies one version of a payload file: a new file, or a rewritten one, differs.
  struct Fingerprint: Codable, Equatable, Sendable {
    let byteCount: Int
    let modificationDate: Date
    let fileNumber: Int

    init(of url: URL) throws {
      let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
      byteCount = (attributes[.size] as? Int) ?? 0
      modificationDate = (attributes[.modificationDate] as? Date) ?? .distantPast
      fileNumber = (attributes[.systemFileNumber] as? Int) ?? 0
    }
  }

  /// A verdict, and the version of the payload it was reached for.
  struct Record: Codable, Sendable, Defaults.Serializable {
    let fingerprint: Fingerprint
    let verdict: Verdict
  }

  /// Where verdicts are kept between checks.
  struct VerdictStore: Sendable {

    // MARK: - Type Properties

    /// Keeps verdicts in the app's defaults, so they outlive the process.
    static let defaults = Self(
      read: { Defaults[.terrainPayloadVerdicts][$0.rawValue] },
      write: { Defaults[.terrainPayloadVerdicts][$0.rawValue] = $1 }
    )

    // MARK: - Instance Properties

    let read: @Sendable (TerrainRegion) -> Record?
    let write: @Sendable (TerrainRegion, Record) -> Void
  }
}

extension Defaults.Keys {
  /// The last verdict ``TerrainPayloadVerifier`` reached for each region's payload, by region ID.
  static let terrainPayloadVerdicts = Key<[String: TerrainPayloadVerifier.Record]>(
    "SF50/3/terrainPayloadVerdicts",
    default: [:]
  )
}
