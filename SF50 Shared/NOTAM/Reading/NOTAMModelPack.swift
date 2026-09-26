public import Defaults
public import Foundation

/// The asset pack that delivers the on-device NOTAM model.
///
/// The pack is published with a `prefetch` policy beside the terrain packs, in the same download
/// manifest, and the downloader extension decides whether the system fetches it
/// (``shouldPrefetch(isDeclined:availableCapacity:downloadSize:)``). It holds the model folder
/// under ``folderPath`` — asset-pack paths share one namespace across packs, so the folder is named
/// for the pack — with the folder's digest (``NOTAMModelDigest``) inside it at ``digestPath``.
public enum NOTAMModelPack {

  // MARK: - Type Properties

  /// The pack's ID in the download manifest.
  public static let id = "notam-model"

  /// The model folder's path within the pack.
  public static let folderPath = "notam-model"

  /// The digest file's path within the pack.
  public static let digestPath = "notam-model/notam-model.sha256"

  /// Free space kept beyond twice the pack's download size, which the system needs to hold the
  /// archive and its expanded contents at once.
  public static let reservedCapacity: Int64 = 1_000_000_000

  /// Whether the pilot deleted the model, which keeps the system from fetching it again until they
  /// download it from Settings.
  public static var isDeclined: Bool { Defaults[.notamModelDeclined] }

  // MARK: - Type Methods

  /// Whether the system should fetch the pack when it offers it.
  ///
  /// The model only proposes values the pilot confirms, so it's never worth crowding out the
  /// pilot's own data: without room for the archive and its expanded contents, the pack is skipped
  /// silently, and the parsers still read formatted reports.
  ///
  /// - Parameters:
  ///   - isDeclined: Whether the pilot deleted the model.
  ///   - availableCapacity: Bytes free for important use, or `nil` when unknown.
  ///   - downloadSize: The pack's download size in bytes.
  public static func shouldPrefetch(isDeclined: Bool, availableCapacity: Int64?, downloadSize: Int)
    -> Bool
  {
    guard !isDeclined, let availableCapacity else { return false }
    return availableCapacity >= Int64(downloadSize) * 2 + reservedCapacity
  }

  /// Bytes free on the device for important use, or `nil` when the volume can't say.
  public static func availableCapacity() -> Int64? {
    try? URL.homeDirectory
      .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
      .volumeAvailableCapacityForImportantUsage
  }
}
