import CryptoKit
public import Foundation

/// The SHA-256 digest a terrain asset pack carries beside its payload.
///
/// Background Assets verifies nothing about a pack's contents, so each pack ships the digest of
/// its own payload in ``TerrainRegion/digestFilename``. Because the digest travels inside the
/// pack, it always describes the version installed, never a newer one on the server.
public enum TerrainPayloadDigest {

  /// The lowercase hexadecimal SHA-256 of the file at `url`.
  ///
  /// The file is memory-mapped rather than read, so a multi-gigabyte payload is hashed without
  /// being resident whole.
  public static func hexDigest(ofFileAt url: URL) throws -> String {
    let data = try Data(contentsOf: url, options: .alwaysMapped)
    return SHA256.hash(data: data).map { unsafe String(format: "%02x", $0) }.joined()
  }
}
