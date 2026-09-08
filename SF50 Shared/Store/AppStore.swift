import Foundation
public import SwiftData

/// The app's persistent store, shared with its extensions through the app group.
///
/// The app, the widget extension and the App Intents surfaces all read the same store at
/// `group.codes.tim.TOLD`. Headless callers — a widget timeline, an intent invoked from Siri — have
/// no `@main` `App` to inherit a container from, so they open their own here.
///
/// Every surface builds its container from the one schema in ``AppSchema``. Two containers
/// describing the same file differently is the kind of disagreement SwiftData settles by migrating.
public enum AppStore {
  /// The identifier of the app group the app and its extensions are entitled to.
  public static let groupIdentifier = "group.codes.tim.TOLD"

  /// The container backing the shared store.
  ///
  /// Opening the store is a precondition for every surface that uses it, and there is no meaningful
  /// recovery from a container that will not open, so failure traps.
  public static let shared: ModelContainer = {
    do { return try makeGroupContainer() } catch {
      fatalError("Couldn’t open the shared model container: \(error)")
    }
  }()

  /// Opens the shared store in the app group.
  public static func makeGroupContainer() throws -> ModelContainer {
    let configuration = ModelConfiguration(
      schema: AppSchema.schema,
      isStoredInMemoryOnly: false,
      groupContainer: .identifier(groupIdentifier)
    )
    return try ModelContainer(for: AppSchema.schema, configurations: [configuration])
  }

  /// Opens a throwaway store held only in memory, for tests, previews and screenshot runs.
  public static func makeInMemoryContainer() throws -> ModelContainer {
    let configuration = ModelConfiguration(schema: AppSchema.schema, isStoredInMemoryOnly: true)
    return try ModelContainer(for: AppSchema.schema, configurations: [configuration])
  }
}
