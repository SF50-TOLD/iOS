import Foundation

/// What a terrain region's files on disk amount to.
public enum TerrainRegionFileState: Equatable, Sendable {

  // MARK: - Cases

  /// Nothing usable is on disk for this region.
  case absent

  /// A payload is present but shorter than the manifest says it should be, so a download is still
  /// running or was cut short.
  case incomplete(bytesOnDisk: Int, expectedBytes: Int)

  /// The payload is present at its full manifest size and ready to load.
  case complete

  /// An LZMA-compressed payload is present and must be expanded before the region can be used.
  case legacyCompressed

  // MARK: - Instance Properties

  /// Whether reaching a usable payload from here means fetching one.
  ///
  /// A short payload counts: it can't be used as it stands, and nothing else will replace it.
  public var needsDownload: Bool {
    switch self {
      case .absent, .incomplete: true
      case .complete, .legacyCompressed: false
    }
  }
}

/// Reads a terrain directory and reports what each region's files amount to.
public struct TerrainRegionInventory: Sendable {

  // MARK: - Instance Properties

  private let directory: URL
  private let manifest: TerrainManifest

  // MARK: - Initializers

  public init(directory: URL, manifest: TerrainManifest) {
    self.directory = directory
    self.manifest = manifest
  }

  // MARK: - Type Methods

  /// Moves a finished download into place as `region`'s payload.
  ///
  /// Where a payload belongs depends only on the directory holding it, so this takes no manifest:
  /// the Background Assets extension stores downloads from a bundle that carries none.
  ///
  /// The move is a rename within one volume, so a concurrent reader sees either the previous payload
  /// or the new one, never a partial file. Background Assets reclaims the source once the callback
  /// that handed it over returns, so this must run before then.
  public static func store(
    _ downloadedFileURL: URL,
    for region: TerrainRegion,
    in directory: URL
  ) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let destinationURL = directory.appendingPathComponent(region.localFilename)
    if FileManager.default.fileExists(atPath: destinationURL.path) {
      try FileManager.default.removeItem(at: destinationURL)
    }
    try FileManager.default.moveItem(at: downloadedFileURL, to: destinationURL)
  }

  // MARK: - Other Methods

  /// Reports what is on disk for `region`.
  ///
  /// A payload counts as usable only when its length matches the manifest, because a download still
  /// being written is indistinguishable from a finished one by existence alone.
  public func state(of region: TerrainRegion) -> TerrainRegionFileState {
    guard let expectedBytes = manifest.region(forID: region.rawValue)?.sizeBytes else {
      return .absent
    }
    if let bytesOnDisk = byteCount(of: localURL(for: region)) {
      return bytesOnDisk == expectedBytes
        ? .complete
        : .incomplete(bytesOnDisk: bytesOnDisk, expectedBytes: expectedBytes)
    }
    if byteCount(of: legacyCompressedURL(for: region)) != nil { return .legacyCompressed }
    return .absent
  }

  /// Where `region`'s payload is stored once it is ready to load.
  public func localURL(for region: TerrainRegion) -> URL {
    directory.appendingPathComponent(region.localFilename)
  }

  /// Where `region`'s LZMA-compressed payload sits while it awaits expansion.
  public func legacyCompressedURL(for region: TerrainRegion) -> URL {
    directory.appendingPathComponent(region.legacyCompressedFilename)
  }

  /// Moves a finished download into place as `region`'s payload.
  public func store(_ downloadedFileURL: URL, for region: TerrainRegion) throws {
    try Self.store(downloadedFileURL, for: region, in: directory)
  }

  private func byteCount(of url: URL) -> Int? {
    try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
  }
}
