import Foundation
import SwiftData
import Testing

@testable import SF50_Shared

/// Nav data and user data are separate files so a cycle can replace one without touching the other.
/// These cover the container that opens both, and the properties the separation depends on.
@Suite
struct `Two Store Container` {
  private static func temporaryLayout() -> StoreLayout {
    .init(
      baseDirectory: FileManager.default.temporaryDirectory
        .appending(path: "TwoStoreTests-\(UUID().uuidString)")
    )
  }

  private static func airport(recordID: String = "TEST") -> Airport {
    .init(
      recordID: recordID,
      locationID: "TEST",
      ICAO_ID: nil,
      name: "Test Airport",
      city: nil,
      dataSource: .NASR,
      latitude: .init(value: 0, unit: .degrees),
      longitude: .init(value: 0, unit: .degrees),
      elevation: .init(value: 0, unit: .feet),
      variation: .init(value: 0, unit: .degrees),
      timeZone: nil
    )
  }

  private static func writeLegacyStore(named name: String, to layout: StoreLayout) throws {
    try layout.createDirectories()
    let configuration = ModelConfiguration(
      "legacy",
      schema: AppSchema.schema,
      url: layout.legacyStoreURL
    )
    let context = ModelContext(
      try ModelContainer(for: AppSchema.schema, configurations: configuration)
    )
    context.insert(Scenario(name: name, operation: .takeoff))
    try context.save()
  }

  private static func writeUserStore(scenarioNames: [String], to layout: StoreLayout) throws {
    try layout.createDirectories()
    let configuration = ModelConfiguration(
      "userData",
      schema: UserDataSchema.schema,
      url: layout.userStoreURL
    )
    let context = ModelContext(
      try ModelContainer(for: UserDataSchema.schema, configurations: configuration)
    )
    for name in scenarioNames { context.insert(Scenario(name: name, operation: .takeoff)) }
    try context.save()
  }

  @Test("both stores are reachable from one container")
  func bothStoresOpen() throws {
    let layout = Self.temporaryLayout()
    defer { try? FileManager.default.removeItem(at: layout.baseDirectory) }

    let context = ModelContext(try AppStore.makeContainer(layout: layout))

    #expect(throws: Never.self) { try context.fetchCount(FetchDescriptor<Airport>()) }
    #expect(throws: Never.self) { try context.fetchCount(FetchDescriptor<Scenario>()) }
  }

  @Test("the nav-data store is created where none exists")
  func navStoreIsBootstrapped() throws {
    let layout = Self.temporaryLayout()
    defer { try? FileManager.default.removeItem(at: layout.baseDirectory) }

    _ = try AppStore.makeContainer(layout: layout)

    #expect(FileManager.default.fileExists(atPath: layout.navStoreURL.path))
  }

  /// The pilot's own entries are what a cycle must not disturb, so they have to be written through
  /// a store the read-only nav configuration is not part of.
  @Test("user data is writable while nav data is not")
  func userDataIsWritable() throws {
    let layout = Self.temporaryLayout()
    defer { try? FileManager.default.removeItem(at: layout.baseDirectory) }

    let context = ModelContext(try AppStore.makeContainer(layout: layout))
    context.insert(Scenario(name: "Test", operation: .takeoff))

    #expect(throws: Never.self) { try context.save() }
    #expect(try context.fetchCount(FetchDescriptor<Scenario>()) == 1)
  }

  /// This is the swap a data cycle performs, and the reason the two stores are separate files.
  ///
  /// The stores are opened in scopes: replacing a file SQLite still has a handle on leaves the
  /// reader on a deleted inode, which is why a downloaded store is installed before any container
  /// opens rather than underneath one.
  @Test("replacing the nav-data store leaves user data alone")
  func swappingNavDataKeepsUserData() throws {
    let layout = Self.temporaryLayout()
    defer { try? FileManager.default.removeItem(at: layout.baseDirectory) }

    do {
      let context = ModelContext(try AppStore.makeContainer(layout: layout))
      context.insert(Scenario(name: "Carried", operation: .landing))
      try context.save()
    }

    let replacement = layout.baseDirectory.appending(path: "replacement.store")
    do {
      let context = ModelContext(
        try AppStore.makeWritableContainer(layout: layout.addressingNavStore(at: replacement))
      )
      context.insert(Self.airport(recordID: "REPLACED"))
      try context.save()
    }

    try StoreLayout.moveStore(from: replacement, to: layout.navStoreURL)

    let reopened = ModelContext(try AppStore.makeContainer(layout: layout))

    #expect(try reopened.fetch(FetchDescriptor<Scenario>()).map(\.name) == ["Carried"])
    #expect(try reopened.fetch(FetchDescriptor<Airport>()).map(\.recordID) == ["REPLACED"])
  }

  @Test("scenarios are carried out of the store that predated the split")
  func legacyScenariosSurvive() throws {
    let layout = Self.temporaryLayout()
    defer { try? FileManager.default.removeItem(at: layout.baseDirectory) }
    try Self.writeLegacyStore(named: "Mine", to: layout)

    let context = ModelContext(try AppStore.makeContainer(layout: layout))

    #expect(try context.fetch(FetchDescriptor<Scenario>()).map(\.name) == ["Mine"])
    #expect(!FileManager.default.fileExists(atPath: layout.legacyStoreURL.path))
  }

  /// What a launch cut short leaves behind: the carry created the user store but was killed before
  /// its save, so the scenarios are still only in the legacy file. Treating the user store as the
  /// marker of a finished carry would strand them there — along with the tens of megabytes of nav
  /// data beside them — for the life of the install.
  @Test("a carry that was cut short is finished on the next launch")
  func interruptedCarryIsRetried() throws {
    let layout = Self.temporaryLayout()
    defer { try? FileManager.default.removeItem(at: layout.baseDirectory) }
    try Self.writeLegacyStore(named: "Mine", to: layout)
    try Self.writeUserStore(scenarioNames: [], to: layout)

    let context = ModelContext(try AppStore.makeContainer(layout: layout))

    #expect(try context.fetch(FetchDescriptor<Scenario>()).map(\.name) == ["Mine"])
    #expect(!FileManager.default.fileExists(atPath: layout.legacyStoreURL.path))
  }

  /// The other way a carry is cut short: it saved, but did not live to retire the legacy store.
  /// Retrying then must not insert everything a second time.
  @Test("a carry that already saved is not repeated")
  func carriedScenariosAreNotDuplicated() throws {
    let layout = Self.temporaryLayout()
    defer { try? FileManager.default.removeItem(at: layout.baseDirectory) }
    try Self.writeLegacyStore(named: "Mine", to: layout)
    try Self.writeUserStore(scenarioNames: ["Mine"], to: layout)

    let context = ModelContext(try AppStore.makeContainer(layout: layout))

    #expect(try context.fetch(FetchDescriptor<Scenario>()).map(\.name) == ["Mine"])
    #expect(!FileManager.default.fileExists(atPath: layout.legacyStoreURL.path))
  }
}
