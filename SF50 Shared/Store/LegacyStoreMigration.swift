import Foundation
import os
import SwiftData

/// Carries what the pilot authored out of the single store that predated the split.
///
/// Before nav data and user data were separated they shared one file. Scenarios have to survive
/// that separation; NOTAMs deliberately do not, because they never outlive a data cycle and the
/// schema-version bump that accompanies this change makes the next launch reload nav data anyway.
struct LegacyStoreMigration {
  private static let logger = Logger(
    subsystem: "codes.tim.SF50-TOLD",
    category: "LegacyStoreMigration"
  )

  let layout: StoreLayout

  /// Moves scenarios into the user store, once, and retires the store they came from.
  ///
  /// The legacy store is what says whether this still has to happen, and it is removed last. An
  /// attempt cut short — the app killed, an extension jetsammed — therefore runs again next launch
  /// rather than stranding the pilot's scenarios in a file nothing opens any more, and leaving its
  /// tens of megabytes on disk forever.
  func migrateIfNeeded() throws {
    guard FileManager.default.fileExists(atPath: layout.legacyStoreURL.path) else { return }

    do { try carryScenariosForward() } catch {
      // A scenario is re-creatable and the defaults are re-seeded, so a failure here costs the
      // pilot their customizations rather than the use of the app. Losing them is better than
      // refusing to launch.
      Self.logger.error("Couldn’t carry scenarios forward: \(error.localizedDescription)")
    }

    StoreLayout.removeStore(at: layout.legacyStoreURL)
  }

  /// Copies the legacy store's scenarios into the user store, unless they are already there.
  ///
  /// Retried launches are the reason for the emptiness check: a run that saved but did not live to
  /// remove the legacy store must not insert every scenario a second time.
  private func carryScenariosForward() throws {
    let context = ModelContext(try userContainer())
    guard try context.fetchCount(FetchDescriptor<Scenario>()) == 0 else {
      Self.logger.notice("The user store already holds scenarios; leaving them alone")
      return
    }

    let scenarios = try readScenarios()
    guard !scenarios.isEmpty else { return }
    for scenario in scenarios { context.insert(scenario.copy()) }
    try context.save()
    Self.logger.notice(
      "Carried \(scenarios.count, privacy: .public) scenarios out of the legacy store"
    )
  }

  private func readScenarios() throws -> [Scenario] {
    let configuration = ModelConfiguration(
      "legacy",
      schema: AppSchema.schema,
      url: layout.legacyStoreURL
    )
    let container = try ModelContainer(for: AppSchema.schema, configurations: configuration)
    return try ModelContext(container).fetch(FetchDescriptor<Scenario>())
  }

  private func userContainer() throws -> ModelContainer {
    let configuration = ModelConfiguration(
      "userData",
      schema: UserDataSchema.schema,
      url: layout.userStoreURL
    )
    return try ModelContainer(for: UserDataSchema.schema, configurations: configuration)
  }
}

extension Scenario {
  /// A detached duplicate of this scenario, for writing into another store.
  fileprivate func copy() -> Scenario {
    let duplicate = Scenario(
      name: name,
      operation: operation,
      deltaTemperature: deltaTemperature,
      deltaWindSpeed: deltaWindSpeed,
      deltaWeight: deltaWeight,
      flapSettingOverride: flapSettingOverride,
      contaminationOverride: contaminationOverride,
      contaminationDepth: contaminationDepth,
      isDryOverride: isDryOverride
    )
    duplicate.rwyCC = rwyCC
    return duplicate
  }
}
