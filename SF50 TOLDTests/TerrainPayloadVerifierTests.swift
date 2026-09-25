import Foundation
import SF50_Shared
import Synchronization
import Testing

@testable import SF50_TOLD

/// Background Assets verifies nothing about a pack's contents, so the digest each pack carries is
/// the only thing standing between a damaged payload and a terrain profile. Hashing a payload takes
/// seconds, so a verdict must also survive until the payload changes, and no longer.
struct TerrainPayloadVerifierTests {

  // MARK: - Methods

  @Test
  func `a payload is intact only when it matches its pack's digest`() throws {
    let payload = try makePayload(Data("terrain".utf8))
    let digest = try TerrainPayloadDigest.hexDigest(ofFileAt: payload)

    let matching = makeVerifier(digest: digest)
    let differing = makeVerifier(digest: String(repeating: "0", count: 64))

    #expect(try matching.verdict(for: .midAtlantic, payloadAt: payload) == .intact)
    #expect(try differing.verdict(for: .midAtlantic, payloadAt: payload) == .damaged)
  }

  /// Packs published before the digest sidecar carry none. Those must stay usable rather than read
  /// as damaged, or every device would lose its terrain until the republish reached it.
  @Test
  func `a pack without a digest is unverifiable, not damaged`() throws {
    let payload = try makePayload(Data("terrain".utf8))

    #expect(
      try makeVerifier(digest: nil).verdict(for: .midAtlantic, payloadAt: payload) == .unverifiable
    )
  }

  @Test
  func `a verdict is reused until the payload changes`() throws {
    let payload = try makePayload(Data("terrain".utf8))
    let lookups = Locked(0)
    let verifier = TerrainPayloadVerifier(
      expectedDigest: { _ in
        lookups.withLock { $0 += 1 }
        return nil
      },
      verdicts: .inMemory()
    )

    _ = try verifier.verdict(for: .midAtlantic, payloadAt: payload)
    _ = try verifier.verdict(for: .midAtlantic, payloadAt: payload)
    #expect(lookups.withLock { $0 } == 1)

    try FileManager.default.removeItem(at: payload)
    try Data("new terrain".utf8).write(to: payload)
    _ = try verifier.verdict(for: .midAtlantic, payloadAt: payload)
    #expect(lookups.withLock { $0 } == 2)
  }

  // MARK: - Fixtures

  private func makeVerifier(digest: String?) -> TerrainPayloadVerifier {
    .init(expectedDigest: { _ in digest }, verdicts: .inMemory())
  }

  private func makePayload(_ contents: Data) throws -> URL {
    let url = URL.temporaryDirectory.appendingPathComponent("terrain-\(UUID().uuidString).srtm")
    try contents.write(to: url)
    return url
  }
}

extension TerrainPayloadVerifier.VerdictStore {
  /// Keeps verdicts for the life of the store only.
  fileprivate static func inMemory() -> Self {
    let records = Locked<[TerrainRegion: TerrainPayloadVerifier.Record]>([:])
    return .init(
      read: { region in records.withLock { $0[region] } },
      write: { region, record in records.withLock { $0[region] = record } }
    )
  }
}

/// A value shared with the closures a verifier calls.
private final class Locked<Value: Sendable>: Sendable {
  private let mutex: Mutex<Value>

  init(_ value: Value) {
    mutex = Mutex(value)
  }

  func withLock<Result: Sendable>(
    _ body: (inout sending Value) -> sending Result
  ) -> sending Result {
    mutex.withLock(body)
  }
}
