public import Foundation

/// Where the app keeps its two persistent stores.
///
/// Nav data and user data are separate files because nav data is replaced whole every cycle: a
/// downloaded store is staged beside the live one and installed by replacing it, which is only
/// atomic if nothing the pilot authored lives in the file being replaced.
///
/// Paths are resolved from a base directory rather than assumed, so tests can build a real
/// two-store container in a temporary directory. Only ``appGroup`` reaches for the group
/// container — which a test bundle stripped of the entitlement cannot do.
public struct StoreLayout: Sendable {
  /// The identifier of the app group the app and its extensions are entitled to.
  public static let groupIdentifier = "group.codes.tim.TOLD"

  private static let navDataDirectoryName = "NavData"
  private static let userDataDirectoryName = "UserData"

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

  private let navStoreOverride: URL?

  /// The nav-data store currently in use.
  public var navStoreURL: URL {
    navStoreOverride ?? navDataDirectory.appending(path: "current.store")
  }

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
  /// - Parameter baseDirectory: The directory to keep both stores under.
  public init(baseDirectory: URL) {
    self.baseDirectory = baseDirectory
    navStoreOverride = nil
  }

  private init(baseDirectory: URL, navStoreOverride: URL?) {
    self.baseDirectory = baseDirectory
    self.navStoreOverride = navStoreOverride
  }

  /// Deletes a store and the write-ahead log and shared-memory files SQLite keeps beside it.
  ///
  /// - Parameter url: The store to delete.
  public static func removeStore(at url: URL) {
    for path in sidecars(of: url) {
      try? FileManager.default.removeItem(atPath: path)
    }
  }

  /// Puts a store, and the files SQLite keeps beside it, where another one was.
  ///
  /// Only safe while no container holds either store open: replacing a file SQLite has a handle on
  /// leaves the reader on a deleted inode. A downloaded store is installed at launch, before any
  /// container opens.
  ///
  /// - Parameters:
  ///   - source: The store to install.
  ///   - destination: Where it should end up.
  public static func moveStore(from source: URL, to destination: URL) throws {
    removeStore(at: destination)
    let fileManager = FileManager.default
    for (from, to) in zip(sidecars(of: source), sidecars(of: destination)) {
      guard fileManager.fileExists(atPath: from) else { continue }
      try fileManager.moveItem(atPath: from, toPath: to)
    }
  }

  private static func sidecars(of url: URL) -> [String] {
    [url.path, "\(url.path)-wal", "\(url.path)-shm"]
  }

  /// The same layout with its nav-data store at `url`.
  ///
  /// An importer writes a store somewhere other than the one in use, and has to open it through the
  /// same pair of configurations that will later read it.
  ///
  /// - Parameter url: Where the nav-data store should be.
  /// - Returns: A layout naming that store.
  public func addressingNavStore(at url: URL) -> Self {
    .init(baseDirectory: baseDirectory, navStoreOverride: url)
  }

  /// Creates the directories both stores live in, if they are not there already.
  public func createDirectories() throws {
    for directory in [navDataDirectory, userDataDirectory] {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
  }
}
