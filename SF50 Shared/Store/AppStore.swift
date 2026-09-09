public import Foundation
public import SwiftData

import Defaults
import os

/// The app's stores, shared with its extensions through the app group.
///
/// Nav data is opened read-only. It is a downloaded artifact replaced whole every cycle, and a
/// store the app cannot write is a store the app cannot leave half-written — which is the failure
/// this separation exists to remove. What the pilot authored lives in its own writable store that
/// no cycle touches.
///
/// Every store is opened through the same pair of configurations, and both are named. SwiftData
/// records the whole container's schema in each store it opens, so a store written by a container
/// of a different shape reads back as one needing migration — and a store opened read-only cannot
/// be migrated. An unnamed second configuration was also historically the difference between a
/// container that opened both stores and one that silently opened only the first.
public enum AppStore {
  private static let navConfigurationName = "navData"
  private static let userConfigurationName = "userData"

  private static let logger = Logger(
    subsystem: "codes.tim.SF50-TOLD",
    category: "AppStore"
  )

  private static let lock = OSAllocatedUnfairLock<ModelContainer?>(initialState: nil)
  private static let hasSweptStaleGenerations = OSAllocatedUnfairLock(initialState: false)

  /// The container backing the app's stores.
  ///
  /// Rebuilt by ``reopen()`` when a newly imported generation is switched to, so a running app
  /// picks up a new dataset without being relaunched.
  public static var shared: ModelContainer {
    lock.withLock { container in
      if let container { return container }
      let opened = openActiveGeneration()
      container = opened
      return opened
    }
  }

  /// Opens both stores, reading the nav-data store of `generation`.
  ///
  /// - Parameters:
  ///   - layout: Where the stores live.
  ///   - generation: Which generation of nav data to read.
  /// - Returns: A container holding a read-only nav store and a writable user store.
  public static func makeContainer(layout: StoreLayout, generation: Int) throws -> ModelContainer {
    try layout.createDirectories()
    try LegacyStoreMigration(layout: layout).migrateIfNeeded()
    try bootstrapIfAbsent(layout: layout, generation: generation)
    return try open(layout: layout, generation: generation, navAllowsSave: false)
  }

  /// Opens both stores against a nav-data generation that must already be on disk.
  ///
  /// Where ``makeContainer(layout:generation:)`` bootstraps an empty store for a generation with no
  /// file, this refuses one. A caller reading a generation to learn what the dataset holds needs a
  /// generation that has gone missing to read as an error, not as a dataset carrying nothing.
  ///
  /// - Parameters:
  ///   - layout: Where the stores live.
  ///   - generation: Which generation of nav data to read.
  /// - Returns: A container holding a read-only nav store and a writable user store.
  /// - Throws: ``Errors/navDataStoreIsMissing(generation:)`` if that generation has no store on
  ///   disk, or the error SwiftData raised trying to open it.
  public static func makeContainerForExistingGeneration(
    layout: StoreLayout,
    generation: Int
  ) throws -> ModelContainer {
    guard layout.navStoreExists(generation: generation) else {
      throw Errors.navDataStoreIsMissing(generation: generation)
    }
    try layout.createDirectories()
    try LegacyStoreMigration(layout: layout).migrateIfNeeded()
    return try open(layout: layout, generation: generation, navAllowsSave: false)
  }

  /// Opens both stores with a nav-data generation writable, for an importer.
  ///
  /// The importer writes through its own container so its bulk transactions queue on their own
  /// coordinator, leaving the store the rest of the app reads read-only — and it writes a
  /// generation nothing is reading yet, so an import that fails costs nothing.
  ///
  /// - Parameters:
  ///   - layout: Where the stores live.
  ///   - generation: The generation to write.
  /// - Returns: A container whose nav-data store accepts writes.
  public static func makeWritableContainer(
    layout: StoreLayout,
    generation: Int
  ) throws -> ModelContainer {
    try layout.createDirectories()
    return try open(layout: layout, generation: generation, navAllowsSave: true)
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

  /// Rebuilds ``shared`` against whichever generation is now current.
  ///
  /// The container holds an open SQLite handle, so a generation is only ever switched to by
  /// opening the new file — never by replacing the old one underneath a reader.
  public static func reopen() {
    lock.withLock { container in
      container = nil
      container = openActiveGeneration()
    }
  }

  private static func openActiveGeneration() -> ModelContainer {
    let layout = StoreLayout.appGroup,
      generation = Defaults[.activeNavDataGeneration]
    // Swept however this process first got a container, including by discarding a bad one: a sweep
    // that had not happened yet would happen on the next reopen instead, under a container that may
    // still be reading what it reclaims.
    defer { sweepStaleGenerationsOnce(layout: layout, keeping: generation) }
    do {
      return try makeContainer(layout: layout, generation: generation)
    } catch {
      // Nav data is a downloaded file, so a corrupt one must not be fatal: discard it and open an
      // empty store, which the app reads as "no data" and offers to download again.
      logger.error("Discarding an unopenable nav-data store: \(error.localizedDescription)")
      StoreLayout.removeStore(at: layout.navStoreURL(generation: generation))
      do { return try makeContainer(layout: layout, generation: generation) } catch {
        fatalError("Couldn’t open the model container: \(error)")
      }
    }
  }

  /// Reclaims superseded generations, but only before this process has opened one.
  ///
  /// A generation is reclaimed at launch and never afterwards. Reopening onto a newer generation
  /// leaves the previous file alone, because the container that was reading it may still be alive —
  /// deleting it would leave that reader on a file that no longer exists, which is exactly what
  /// numbering generations avoids.
  private static func sweepStaleGenerationsOnce(layout: StoreLayout, keeping generation: Int) {
    let shouldSweep = hasSweptStaleGenerations.withLock { hasSwept in
      defer { hasSwept = true }
      return !hasSwept
    }
    guard shouldSweep else { return }
    layout.removeNavStores(exceptGeneration: generation)
  }

  private static func open(
    layout: StoreLayout,
    generation: Int,
    navAllowsSave: Bool
  ) throws -> ModelContainer {
    let navData = ModelConfiguration(
      navConfigurationName,
      schema: NavDataSchema.schema,
      url: layout.navStoreURL(generation: generation),
      allowsSave: navAllowsSave
    )
    let userData = ModelConfiguration(
      userConfigurationName,
      schema: UserDataSchema.schema,
      url: layout.userStoreURL
    )
    return try ModelContainer(for: AppSchema.schema, configurations: navData, userData)
  }

  /// Creates an empty nav-data store where none exists.
  ///
  /// A read-only configuration cannot create the file it is pointed at, and an empty store written
  /// by this binary matches this binary's schema by construction — which is also why no store needs
  /// to ship inside the app.
  ///
  /// It is created through the same pair of configurations that will read it, for the reason given
  /// on the type.
  private static func bootstrapIfAbsent(layout: StoreLayout, generation: Int) throws {
    guard !layout.navStoreExists(generation: generation) else { return }
    _ = try open(layout: layout, generation: generation, navAllowsSave: true)
  }

  /// Reasons a store couldn’t be opened.
  public enum Errors: Swift.Error, LocalizedError {
    /// The generation asked for has no store on disk.
    case navDataStoreIsMissing(generation: Int)

    public var errorDescription: String? {
      String(localized: "Couldn’t open the navigation data.", bundle: .sharedFramework)
    }

    public var failureReason: String? {
      switch self {
        case .navDataStoreIsMissing(let generation):
          String(
            localized: "Generation \(generation, format: .number) has no database on disk.",
            bundle: .sharedFramework
          )
      }
    }

    public var recoverySuggestion: String? {
      String(localized: "Try downloading the navigation data again.", bundle: .sharedFramework)
    }
  }
}
