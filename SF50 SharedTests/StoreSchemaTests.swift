import Foundation
import SwiftData
import Testing

@testable import SF50_Shared

/// Nav data and user data are kept in separate model sets because nav data is replaced wholesale
/// every cycle. These assert the properties that split depends on, and pin the shape a prebuilt
/// store has to match.
@Suite
struct `Store Schema` {
  /// The nav-data schema's shape, as of the last deliberate change to it.
  ///
  /// A prebuilt store is written by one binary and read by another, so the shape they agree on is
  /// part of the published contract rather than an implementation detail. Pinning it here turns an
  /// accidental model edit into a failing test rather than a store the app quietly migrates.
  private static let navDataFingerprint =
    "e34a40fabe9d77b410a12986d67fe8006ac1ad4d32735c46a3eeb98c9908feef"

  @Test("the two stores declare no model in common")
  func storesAreDisjoint() {
    let navNames = Set(NavDataSchema.models.map { String(describing: $0) })
    let userNames = Set(UserDataSchema.models.map { String(describing: $0) })

    #expect(navNames.isDisjoint(with: userNames))
  }

  @Test("every model the app persists belongs to one of the two stores")
  func storesAccountForEveryModel() {
    let declared = Set(AppSchema.models.map { String(describing: $0) })
    let entities = Set(AppSchema.schema.entities.map(\.name))

    #expect(declared == entities)
  }

  @Test("the nav-data schema matches its pinned fingerprint")
  func fingerprintIsPinned() {
    #expect(NavDataSchema.fingerprint == Self.navDataFingerprint)
  }

  @Test("a container opens the store")
  func containerOpens() throws {
    let container = try AppStore.makeInMemoryContainer()
    let context = ModelContext(container)

    #expect(throws: Never.self) { try context.fetchCount(FetchDescriptor<Airport>()) }
    #expect(throws: Never.self) { try context.fetchCount(FetchDescriptor<Scenario>()) }
  }
}
