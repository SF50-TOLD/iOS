public import Foundation
import os
public import SwiftData

/// The app's two persistent stores, shared with its extensions through the app group.
///
/// Nav data is opened read-only. It is a downloaded artifact replaced whole every cycle, and a
/// store the app cannot write is a store the app cannot leave half-written — which is the failure
/// this separation exists to remove. What the pilot authored lives in its own writable store that
/// no cycle touches.
///
/// Both configurations are named. An unnamed second configuration was historically the difference
/// between a container that opened both stores and one that silently opened only the first.
public enum AppStore {
  private static let navConfigurationName = "navData"
  private static let userConfigurationName = "userData"

  private static let logger = Logger(
    subsystem: "codes.tim.SF50-TOLD",
    category: "AppStore"
  )

  /// The container backing both shared stores.
  public static let shared: ModelContainer = {
    let layout = StoreLayout.appGroup
    do {
      return try makeContainer(layout: layout)
    } catch {
      // Nav data is a downloaded file, so a corrupt one must not be fatal: discard it and open an
      // empty store, which the app reads as "no data" and offers to download again.
      logger.error("Discarding an unopenable nav-data store: \(error.localizedDescription)")
      StoreLayout.removeStore(at: layout.navStoreURL)
      do { return try makeContainer(layout: layout) } catch {
        fatalError("Couldn’t open the model container: \(error)")
      }
    }
  }()

  /// Opens both stores as the layout arranges them.
  ///
  /// - Parameter layout: Where the stores live.
  /// - Returns: A container holding a read-only nav store and a writable user store.
  public static func makeContainer(layout: StoreLayout) throws -> ModelContainer {
    try layout.createDirectories()
    try LegacyStoreMigration(layout: layout).migrateIfNeeded()
    try bootstrapIfAbsent(layout: layout)
    return try open(layout: layout, navAllowsSave: false)
  }

  private static func open(layout: StoreLayout, navAllowsSave: Bool) throws -> ModelContainer {
    let navData = ModelConfiguration(
      navConfigurationName,
      schema: NavDataSchema.schema,
      url: layout.navStoreURL,
      allowsSave: navAllowsSave
    )
    let userData = ModelConfiguration(
      userConfigurationName,
      schema: UserDataSchema.schema,
      url: layout.userStoreURL
    )
    return try ModelContainer(for: AppSchema.schema, configurations: navData, userData)
  }

  /// Opens both stores with the nav-data store writable, for an importer.
  ///
  /// The importer writes through its own container so its bulk transactions queue on their own
  /// coordinator, leaving the store the rest of the app reads read-only.
  ///
  /// It opens the same pair of configurations rather than the nav store alone. SwiftData records
  /// the whole container's schema in every store it opens, so a nav store written by a container
  /// of a different shape reads back as one needing migration — and a store opened read-only
  /// cannot be migrated.
  ///
  /// - Parameter layout: Where the stores live, usually with the nav store addressed elsewhere.
  /// - Returns: A container whose nav-data store accepts writes.
  public static func makeWritableContainer(layout: StoreLayout) throws -> ModelContainer {
    try layout.createDirectories()
    return try open(layout: layout, navAllowsSave: true)
  }

  /// Opens throwaway stores held only in memory, for tests, previews and screenshot runs.
  ///
  /// Nav data is writable here: seeding a test or a preview means inserting airports.
  public static func makeInMemoryContainer() throws -> ModelContainer {
    let navData = ModelConfiguration(
      navConfigurationName,
      schema: NavDataSchema.schema,
      isStoredInMemoryOnly: true
    )
    let userData = ModelConfiguration(
      userConfigurationName,
      schema: UserDataSchema.schema,
      isStoredInMemoryOnly: true
    )
    return try ModelContainer(for: AppSchema.schema, configurations: navData, userData)
  }

  /// Creates an empty nav-data store where none exists.
  ///
  /// A read-only configuration cannot create the file it is pointed at, and an empty store written
  /// by this binary matches this binary's schema by construction — which is also why no store needs
  /// to ship inside the app.
  ///
  /// It is created through the same pair of configurations that will read it. SwiftData records the
  /// whole container's schema in each store it opens, so a store stamped by a container of a
  /// different shape reads back as one needing migration — and migrating a store opened read-only
  /// fails outright.
  private static func bootstrapIfAbsent(layout: StoreLayout) throws {
    guard !FileManager.default.fileExists(atPath: layout.navStoreURL.path) else { return }
    _ = try open(layout: layout, navAllowsSave: true)
  }
}
