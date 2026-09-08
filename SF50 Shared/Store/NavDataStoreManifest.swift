public import Foundation

/// Describes one cycle's prebuilt nav-data store.
///
/// One manifest is published per cycle, named for that cycle's date, and each states the window it
/// is effective for. There is deliberately no "latest" pointer: a mutable one cannot say *which*
/// cycle is current, and a stale one is indistinguishable from a fresh one — which for data with a
/// hard 28-day validity is not a distinction to leave to chance.
///
/// A client computes the cycle it wants from the AIRAC calendar and asks for that manifest by name.
/// When a publish has failed, the cycle before it is still there to fall back to, still carrying its
/// own expiry.
public struct NavDataStoreManifest: Codable, Sendable {
  /// The cycle this dataset is published for, as `YYYY-MM-DD`.
  public let cycle: String

  /// When the dataset becomes effective.
  public let effective: Date

  /// When the dataset expires.
  public let expires: Date

  /// The shape of the store, as ``NavDataSchema/fingerprint`` computes it.
  ///
  /// Checked before the store is downloaded, let alone opened. SwiftData answers a near-miss by
  /// migrating rather than by refusing, so a client that opened first would get a silent, slow
  /// migration where it wanted a clean fall back to importing the dataset itself.
  public let schemaFingerprint: String

  /// The app schema version this store was built for.
  public let schemaVersion: Int

  /// The compressed store this manifest describes.
  public let store: Asset

  /// What the store holds, for a client to check it against after opening it.
  public let counts: Counts

  /// When the OurAirports data folded into this dataset was last processed, if it carries any.
  ///
  /// The app reports this beside the FAA cycles, so it has to survive the trip through a prebuilt
  /// store: nothing about the store file itself records when its non-FAA airports were gathered.
  /// Optional because a manifest published before this was carried has none to give.
  public let ourAirportsLastUpdated: Date?

  /// Whether this cycle's data is in force right now.
  public var isEffective: Bool { isEffective(at: .now) }

  /// Whether the store this manifest describes has the shape this build reads.
  ///
  /// Worth asking before the store is downloaded, let alone opened: SwiftData answers a near-miss
  /// by migrating the store rather than by refusing it, so a client that opened first would get a
  /// silent, slow migration where it wanted a clean fall back to building the dataset itself.
  public var matchesSchema: Bool {
    schemaFingerprint == NavDataSchema.fingerprint && schemaVersion == latestSchemaVersion
  }

  /// Creates a manifest.
  ///
  /// - Parameters:
  ///   - cycle: The cycle this dataset is published for.
  ///   - effective: When the dataset becomes effective.
  ///   - expires: When the dataset expires.
  ///   - schemaFingerprint: The shape of the store.
  ///   - schemaVersion: The app schema version the store was built for.
  ///   - store: The compressed store.
  ///   - counts: What the store holds.
  ///   - ourAirportsLastUpdated: When this dataset's OurAirports data was last processed.
  public init(
    cycle: String,
    effective: Date,
    expires: Date,
    schemaFingerprint: String,
    schemaVersion: Int,
    store: Asset,
    counts: Counts,
    ourAirportsLastUpdated: Date?
  ) {
    self.cycle = cycle
    self.effective = effective
    self.expires = expires
    self.schemaFingerprint = schemaFingerprint
    self.schemaVersion = schemaVersion
    self.store = store
    self.counts = counts
    self.ourAirportsLastUpdated = ourAirportsLastUpdated
  }

  /// Whether this cycle's data is in force at a given moment.
  ///
  /// The window is half-open. A cycle takes effect at the instant its manifest names and stops
  /// being in force at the instant it expires, which is the same instant its successor takes
  /// effect, so exactly one cycle is in force at any moment.
  ///
  /// Judging a cycle on the window it publishes, rather than on the client's own reckoning of
  /// which cycle is current, is what lets a client accept a cycle that is still in force but is
  /// not the one today's calendar names — and refuse one that has already lapsed.
  ///
  /// - Parameter date: The moment to judge the cycle at.
  /// - Returns: Whether the cycle's data is in force.
  public func isEffective(at date: Date) -> Bool {
    effective <= date && date < expires
  }

  /// A published file.
  public struct Asset: Codable, Sendable {
    /// The file's name, relative to the manifest.
    public let filename: String

    /// The file's size in bytes, compressed.
    public let bytes: Int

    /// The file's SHA-256 digest, as lowercase hexadecimal.
    public let sha256: String

    /// Creates an asset description.
    ///
    /// - Parameters:
    ///   - filename: The file's name, relative to the manifest.
    ///   - bytes: The file's compressed size.
    ///   - sha256: The file's SHA-256 digest.
    public init(filename: String, bytes: Int, sha256: String) {
      self.filename = filename
      self.bytes = bytes
      self.sha256 = sha256
    }
  }

  /// How many rows of each kind the store holds.
  public struct Counts: Codable, Sendable {
    /// Airports in the store.
    public let airports: Int

    /// Runways in the store.
    public let runways: Int

    /// Obstacles in the store.
    public let obstacles: Int

    /// Creates a row count.
    ///
    /// - Parameters:
    ///   - airports: Airports in the store.
    ///   - runways: Runways in the store.
    ///   - obstacles: Obstacles in the store.
    public init(airports: Int, runways: Int, obstacles: Int) {
      self.airports = airports
      self.runways = runways
      self.obstacles = obstacles
    }
  }
}
