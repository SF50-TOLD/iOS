import Foundation
public import SwiftData

/// The SwiftData store in the shared app group container.
///
/// The app, the widget extension, and the App Intents surfaces all read the same nav-data store at
/// `group.codes.tim.TOLD`. Headless callers — a widget timeline, an intent invoked from Siri — have no
/// `@main` `App` to inherit a container from, so they open their own here.
public enum AppGroupStore {
  /// The identifier of the app group both the app and its extensions are entitled to.
  public static let groupIdentifier = "group.codes.tim.TOLD"

  /// The model container backing the shared store.
  ///
  /// The schema matches the app's own container exactly. Headless surfaces now open the store from
  /// inside the app process as well as the extension, and two containers describing the same file
  /// differently is the kind of disagreement SwiftData resolves by migrating.
  ///
  /// Opening the store is a precondition for every surface that uses it; there is no meaningful
  /// recovery from a container that will not open, so failure traps.
  public static let container: ModelContainer = {
    let schema = Schema([
      Airport.self,
      Runway.self,
      NOTAM.self,
      Scenario.self,
      Cycle.self,
      Obstacle.self,
      Procedure.self,
      ProcedureSegment.self,
      Leg.self,
      Navaid.self
    ])
    let configuration = ModelConfiguration(
      schema: schema,
      isStoredInMemoryOnly: false,
      groupContainer: .identifier(groupIdentifier)
    )

    do {
      return try ModelContainer(for: schema, configurations: [configuration])
    } catch {
      fatalError("Failed to create ModelContainer: \(error)")
    }
  }()
}
