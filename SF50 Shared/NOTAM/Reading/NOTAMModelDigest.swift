import CryptoKit
public import Foundation

/// The SHA-256 digest of a NOTAM model folder, which its asset pack carries at
/// ``NOTAMModelPack/digestPath``.
///
/// Background Assets verifies nothing about a pack's contents, so the publisher records this digest
/// and the app checks it before loading the model. The folder holds several files, some inside the
/// Core AI model's own directory, so the digest covers them all: one line per regular file,
/// `<SHA-256>  <relative path>`, sorted by path, and the SHA-256 of those lines. The digest file
/// itself is left out.
public enum NOTAMModelDigest {

  // MARK: - Type Methods

  /// The lowercase hexadecimal digest of the model folder at `folder`.
  ///
  /// Each file is memory-mapped rather than read, so the model's weights are hashed without being
  /// resident whole.
  public static func hexDigest(ofFolderAt folder: URL) throws -> String {
    let listing = try relativeFilePaths(in: folder)
      .map { path in
        let data = try Data(contentsOf: folder.appending(path: path), options: .alwaysMapped)
        return "\(hex(SHA256.hash(data: data)))  \(path)\n"
      }
      .joined()
    return hex(SHA256.hash(data: Data(listing.utf8)))
  }

  private static func relativeFilePaths(in folder: URL) throws -> [String] {
    let root = folder.standardizedFileURL.path(percentEncoded: false)
    let digestName = URL(filePath: NOTAMModelPack.digestPath).lastPathComponent
    guard
      let enumerator = FileManager.default.enumerator(
        at: folder,
        includingPropertiesForKeys: [.isRegularFileKey]
      )
    else { return [] }
    return try enumerator.compactMap { item -> String? in
      guard let url = item as? URL,
        try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true,
        url.lastPathComponent != digestName
      else { return nil }
      return String(url.standardizedFileURL.path(percentEncoded: false).dropFirst(root.count))
        .trimmingPrefix("/").description
    }
    .sorted()
  }

  private static func hex(_ digest: SHA256.Digest) -> String {
    digest.map { unsafe String(format: "%02x", $0) }.joined()
  }
}
