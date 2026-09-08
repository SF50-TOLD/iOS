public import Foundation

/// Where the app keeps its stores.
///
/// Nav data is replaced whole every cycle, and the replacement is a new file rather than a rewrite
/// of the old one: each import writes the next *generation*, and the app switches to it by
/// recording which generation is current. Nothing ever overwrites a store another process might
/// still have open, and an import that never finishes leaves a file nobody points at.
///
/// What the pilot authored lives in one store that no cycle touches.
///
/// Paths are resolved from a base directory rather than assumed, so tests can build real stores in
/// a temporary directory. Only ``appGroup`` reaches for the group container — which a test bundle
/// stripped of the entitlement cannot do.
public struct StoreLayout: Sendable {
  /// The identifier of the app group the app and its extensions are entitled to.
  public static let groupIdentifier = "group.codes.tim.TOLD"

  private static let navDataDirectoryName = "NavData"
  private static let userDataDirectoryName = "UserData"
  private static let navStorePrefix = "navdata-"
  private static let navStoreSuffix = ".store"

  /// The layout rooted in the shared app-group container.
  ///
  /// Traps if the container is unreachable: every surface that reads the store needs it, and there
  /// is no meaningful recovery from an app that is not in its own app group.
  public static var appGroup: Self {
    guard
      let container = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: groupIdentifier
      )
    else {
      fatalError("The app group \(groupIdentifier) is unreachable")
    }
    return .init(baseDirectory: container.appending(path: "Library/Application Support"))
  }

  /// The directory the stores live under.
  public let baseDirectory: URL

  /// The store holding what the pilot authored.
  public var userStoreURL: URL {
    userDataDirectory.appending(path: "user.store")
  }

  /// The single store both kinds of data shared before they were separated.
  ///
  /// Retained so an install predating the split can have its scenarios carried across.
  public var legacyStoreURL: URL {
    baseDirectory.appending(path: "default.store")
  }

  private var navDataDirectory: URL {
    baseDirectory.appending(path: Self.navDataDirectoryName)
  }

  private var userDataDirectory: URL {
    baseDirectory.appending(path: Self.userDataDirectoryName)
  }

  /// Creates a layout rooted at `baseDirectory`.
  ///
  /// - Parameter baseDirectory: The directory to keep the stores under.
  public init(baseDirectory: URL) {
    self.baseDirectory = baseDirectory
  }

  /// Deletes a store and the write-ahead log and shared-memory files SQLite keeps beside it.
  ///
  /// - Parameter url: The store to delete.
  public static func removeStore(at url: URL) {
    for path in [url.path, "\(url.path)-wal", "\(url.path)-shm"] {
      try? FileManager.default.removeItem(atPath: path)
    }
  }

  /// The nav-data store holding a given generation of the dataset.
  ///
  /// - Parameter generation: Which generation to address.
  /// - Returns: That generation's store, whether or not it exists yet.
  public func navStoreURL(generation: Int) -> URL {
    navDataDirectory.appending(path: "\(Self.navStorePrefix)\(generation)\(Self.navStoreSuffix)")
  }

  /// Every generation with a store on disk, in ascending order.
  public func navStoreGenerations() -> [Int] {
    let contents =
      (try? FileManager.default.contentsOfDirectory(atPath: navDataDirectory.path)) ?? []
    return
      contents
      .compactMap { name in
        guard name.hasPrefix(Self.navStorePrefix), name.hasSuffix(Self.navStoreSuffix) else {
          return nil
        }
        return Int(name.dropFirst(Self.navStorePrefix.count).dropLast(Self.navStoreSuffix.count))
      }
      .sorted()
  }

  /// Deletes every nav-data store except the one in use.
  ///
  /// Called at launch, when nothing holds a superseded generation open. An import that failed
  /// part-way leaves a store nobody points at, and this is what reclaims it.
  ///
  /// - Parameter generation: The generation to keep.
  public func removeNavStores(exceptGeneration generation: Int) {
    for stale in navStoreGenerations() where stale != generation {
      Self.removeStore(at: navStoreURL(generation: stale))
    }
  }

  /// Creates the directories the stores live in, if they are not there already.
  public func createDirectories() throws {
    for directory in [navDataDirectory, userDataDirectory] {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
  }
}
