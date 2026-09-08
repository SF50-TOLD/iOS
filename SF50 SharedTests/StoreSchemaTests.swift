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
    "d46f345bdc1174823b0a2de34bc754d1af5e3c5416d560feb27102856e25c323"

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

  /// SwiftData cannot express a relationship between models in different store configurations, and
  /// answers one by quietly pulling the destination into the configuration rather than by raising
  /// an error. A schema that has grown past the models it names is the only symptom, and it means
  /// the two stores would open as one.
  @Test("neither store drags in a model it does not name")
  func storesDoNotExpand() {
    let navDeclared = Set(NavDataSchema.models.map { String(describing: $0) })
    let userDeclared = Set(UserDataSchema.models.map { String(describing: $0) })

    #expect(Set(NavDataSchema.schema.entities.map(\.name)) == navDeclared)
    #expect(Set(Schema(UserDataSchema.models).entities.map(\.name)) == userDeclared)
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
