import Defaults
import Foundation
import SwiftData
import Testing

@testable import SF50_Shared

/// Switching to a newly imported dataset is a single recorded number, taken only after the new
/// store has been opened and found to hold airports. These are the tests that earn the word
/// "atomic": whatever happens to an import, the dataset in use is either replaced wholly or not
/// at all.
@Suite(.serialized)
struct `Nav Data Store Install` {
  private static func airport(recordID: String) -> Airport {
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

  private static func temporaryLayout() -> StoreLayout {
    .init(
      baseDirectory: FileManager.default.temporaryDirectory
        .appending(path: "InstallerTests-\(UUID().uuidString)")
    )
  }

  private static func write(_ recordID: String, generation: Int, in layout: StoreLayout) throws {
    let context = ModelContext(
      try AppStore.makeWritableContainer(layout: layout, generation: generation)
    )
    context.insert(airport(recordID: recordID))
    try context.save()
  }

  @Test("a generation holding a dataset is switched to")
  func installsAGoodStore() throws {
    let layout = Self.temporaryLayout()
    defer { cleanUp(layout) }
    let installer = NavDataStoreInstaller(layout: layout)

    let generation = installer.reserveGeneration()
    try Self.write("IMPORTED", generation: generation, in: layout)
    try installer.install(generation: generation)

    #expect(installer.activeGeneration == generation)
  }

  /// An import that produced nothing must not become the dataset the pilot flies on.
  @Test("a generation holding no airports is refused, and the dataset in use is kept")
  func refusesAnEmptyStore() throws {
    let layout = Self.temporaryLayout()
    defer { cleanUp(layout) }
    let installer = NavDataStoreInstaller(layout: layout)
    try Self.write("LIVE", generation: installer.activeGeneration, in: layout)
    let live = installer.activeGeneration

    let generation = installer.reserveGeneration()
    _ = try AppStore.makeWritableContainer(layout: layout, generation: generation)

    #expect(throws: NavDataStoreInstaller.Errors.storeIsEmpty) {
      try installer.install(generation: generation)
    }
    #expect(installer.activeGeneration == live)
  }

  @Test("a reserved generation is one nothing is using")
  func reservesAnUnusedGeneration() throws {
    let layout = Self.temporaryLayout()
    defer { cleanUp(layout) }
    let installer = NavDataStoreInstaller(layout: layout)

    let first = installer.reserveGeneration()
    try Self.write("FIRST", generation: first, in: layout)
    try installer.install(generation: first)
    let second = installer.reserveGeneration()

    #expect(second > first)
    #expect(!FileManager.default.fileExists(atPath: layout.navStoreURL(generation: second).path))
  }

  private func cleanUp(_ layout: StoreLayout) {
    Defaults.reset(.activeNavDataGeneration)
    try? FileManager.default.removeItem(at: layout.baseDirectory)
  }
}
