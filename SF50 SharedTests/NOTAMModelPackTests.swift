import Foundation
import Testing

@testable import SF50_Shared

/// The downloader extension prefetches the NOTAM model only when the pilot hasn't deleted it and
/// the device has room; the app checks the model against the digest its pack carries.
struct `NOTAM model pack` {
  private static let packSize = 650_000_000

  private static func folder(_ files: KeyValuePairs<String, String>) throws -> URL {
    let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
    for (path, contents) in files {
      let url = folder.appending(path: path)
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try Data(contents.utf8).write(to: url)
    }
    return folder
  }

  @Test(arguments: [
    (false, Int64?.some(3_000_000_000), true),
    (false, Int64?.some(2_000_000_000), false),
    (true, Int64?.some(50_000_000_000), false),
    (false, Int64?.none, false)
  ])
  func `prefetches only when wanted and there's room`(
    _ isDeclined: Bool,
    _ availableCapacity: Int64?,
    _ expected: Bool
  ) {
    #expect(
      NOTAMModelPack.shouldPrefetch(
        isDeclined: isDeclined,
        availableCapacity: availableCapacity,
        downloadSize: Self.packSize
      ) == expected
    )
  }

  @Test
  func `digests a folder's files, not its digest or the order they were written`() throws {
    let first = try Self.folder(["tokenizer.json": "a", "model.aimodel/main.mlirb": "b"]),
      second = try Self.folder([
        "model.aimodel/main.mlirb": "b", "tokenizer.json": "a", "notam-model.sha256": "x"
      ]),
      changed = try Self.folder(["tokenizer.json": "a", "model.aimodel/main.mlirb": "c"])

    let digest = try NOTAMModelDigest.hexDigest(ofFolderAt: first)
    #expect(try NOTAMModelDigest.hexDigest(ofFolderAt: second) == digest)
    #expect(try NOTAMModelDigest.hexDigest(ofFolderAt: changed) != digest)
  }
}
