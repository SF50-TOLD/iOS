import Foundation
import SF50_Shared
import Testing

@testable import SF50_TOLD

/// The publish job runs some hours into the day a cycle takes effect, so for part of that day the
/// current cycle's manifest is missing while its property list is already up. What the walk-back
/// reaches for in that window is the cycle before it — whose store expired at midnight. Installing
/// that one reports success, which stops the fall back to the import, and leaves the app asking for
/// a reload it has just been told it completed.
struct `Prebuilt cycle selection` {

  // MARK: - Type Methods

  private static func manifest(effective: Date, expires: Date) -> NavDataStoreManifest {
    .init(
      cycle: "2026-09-03",
      effective: effective,
      expires: expires,
      schemaFingerprint: NavDataSchema.fingerprint,
      schemaVersion: latestSchemaVersion,
      store: .init(
        filename: "2026-09-03.store.lzma",
        bytes: 1024,
        sha256: String(repeating: "0", count: 64)
      ),
      counts: .init(airports: 1, runways: 1, obstacles: 1),
      ourAirportsLastUpdated: nil
    )
  }

  // MARK: - Tests

  @Test
  func `rejects a cycle that expired before the store would be installed`() {
    let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    let expired = Self.manifest(
      effective: now.addingTimeInterval(-28 * 86400),
      expires: now.addingTimeInterval(-3600)
    )

    #expect(!expired.isEffective(at: now))
  }

  @Test
  func `rejects a cycle at the instant it expires`() {
    let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    let lapsing = Self.manifest(effective: now.addingTimeInterval(-28 * 86400), expires: now)

    #expect(!lapsing.isEffective(at: now))
  }

  @Test
  func `accepts an older cycle that is still in force`() {
    let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    let current = Self.manifest(
      effective: now.addingTimeInterval(-14 * 86400),
      expires: now.addingTimeInterval(14 * 86400)
    )

    #expect(current.isEffective(at: now))
  }

  @Test
  func `rejects a cycle published ahead of the day it takes effect`() {
    let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    let future = Self.manifest(
      effective: now.addingTimeInterval(86400),
      expires: now.addingTimeInterval(29 * 86400)
    )

    #expect(!future.isEffective(at: now))
  }
}
