import BackgroundAssets
import Defaults
import Foundation
import SF50_Shared
import System

/// Checks an installed NOTAM model folder against the digest its asset pack carries.
///
/// Background Assets verifies nothing about a pack's contents, so a model damaged in transit or on
/// disk would otherwise be loaded. Hashing the whole folder takes seconds, so each verdict is kept
/// against the folder's fingerprint — every file's size, modification date and file number — and
/// reused until the system installs a new version of the pack.
struct NOTAMModelVerifier: Sendable {

  // MARK: - Instance Properties

  /// The digest the installed pack carries, or `nil` when it carries none.
  private let expectedDigest: @Sendable () -> String?

  // MARK: - Initializers

  init(expectedDigest: @escaping @Sendable () -> String? = Self.installedPackDigest) {
    self.expectedDigest = expectedDigest
  }

  // MARK: - Type Methods

  private static func installedPackDigest() -> String? {
    guard
      let data = try? AssetPackManager.shared.contents(
        at: FilePath(NOTAMModelPack.digestPath),
        searchingInAssetPackWithID: NOTAMModelPack.id
      )
    else { return nil }
    return String(bytes: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func fingerprint(of folder: URL) throws -> [String] {
    let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
    guard let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys)
    else { return [] }
    return try files.compactMap { item -> String? in
      guard let url = item as? URL,
        try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true
      else { return nil }
      let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
      let size = (attributes[.size] as? Int) ?? 0,
        modified = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0,
        fileNumber = (attributes[.systemFileNumber] as? Int) ?? 0
      return "\(url.lastPathComponent) \(size) \(modified) \(fileNumber)"
    }
    .sorted()
  }

  // MARK: - Instance Methods

  /// Whether the model folder at `folder` is the one the installed pack describes.
  ///
  /// A pack without a digest isn't trusted: the model is loaded only when its files are known to be
  /// the ones published.
  ///
  /// - Throws: If the folder can't be read, which says nothing about whether it's intact.
  func isIntact(folderAt folder: URL) throws -> Bool {
    let fingerprint = try Self.fingerprint(of: folder)
    if let recorded = Defaults[.notamModelVerdict], recorded.fingerprint == fingerprint {
      return recorded.isIntact
    }
    guard let expected = expectedDigest() else { return false }
    let isIntact = try NOTAMModelDigest.hexDigest(ofFolderAt: folder) == expected.lowercased()
    Defaults[.notamModelVerdict] = Record(fingerprint: fingerprint, isIntact: isIntact)
    return isIntact
  }

  // MARK: - Nested Types

  /// A verdict, and the version of the folder it was reached for.
  struct Record: Codable, Sendable, Defaults.Serializable {
    let fingerprint: [String]
    let isIntact: Bool
  }
}

extension Defaults.Keys {
  /// The last verdict ``NOTAMModelVerifier`` reached, with the folder version it was reached for.
  static let notamModelVerdict = Key<NOTAMModelVerifier.Record?>("SF50/3/notamModelVerdict")
}
