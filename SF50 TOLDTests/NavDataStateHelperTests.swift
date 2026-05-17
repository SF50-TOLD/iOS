import Defaults
import Foundation
import SF50_Shared
import SwiftData
import Testing

@testable import SF50_TOLD

/// Regression coverage for SF50-TOLD-20.
///
/// The launch hang was caused by `NavDataLoaderViewModel` computing its loader
/// state with a synchronous `container.mainContext` fetch on the MainActor while
/// the `NavDataLoader` `@ModelActor` held the persistent store coordinator during
/// a bulk nav-data import. The fix routes all state computation through
/// `NavDataStateHelper.fetchState(context:)` running on a background
/// `ModelContext(container)`.
///
/// These tests pin the contract the fix depends on: `fetchState` must produce
/// correct results when invoked against a background context that is *not* the
/// container's main context, so the view model never has to touch the main
/// context to decide whether to show the loader.
@MainActor
struct NavDataStateHelperTests {
  private func makeContainer() throws -> ModelContainer {
    try ModelContainer(
      for: Airport.self,
      Runway.self,
      NOTAM.self,
      Scenario.self,
      Cycle.self,
      Obstacle.self,
      Procedure.self,
      ProcedureSegment.self,
      Leg.self,
      configurations: .init(isStoredInMemoryOnly: true)
    )
  }

  private func withSchemaVersion<T>(_ version: Int, _ body: () throws -> T) rethrows -> T {
    let original = Defaults[.schemaVersion]
    Defaults[.schemaVersion] = version
    defer { Defaults[.schemaVersion] = original }
    return try body()
  }

  @Test
  func reportsNoDataWhenStoreIsEmpty() throws {
    let container = try makeContainer()
    let backgroundContext = ModelContext(container)

    let state = try withSchemaVersion(latestSchemaVersion) {
      try NavDataStateHelper.fetchState(context: backgroundContext)
    }

    #expect(state.noData)
    #expect(state.needsLoad)
    #expect(!state.canSkip)
  }

  @Test
  func backgroundContextSeesDataWrittenByMainContext() throws {
    let container = try makeContainer()

    let (airport, runways) = AirportBuilder.KSQL.build()
    container.mainContext.insert(airport)
    for runway in runways { container.mainContext.insert(runway) }
    container.mainContext.insert(
      Cycle(
        dataSource: .nasr,
        name: "2501",
        effective: Date.now.addingTimeInterval(-86_400),
        expires: Date.now.addingTimeInterval(86_400)
      )
    )
    try container.mainContext.save()

    let backgroundContext = ModelContext(container)
    let state = try withSchemaVersion(latestSchemaVersion) {
      try NavDataStateHelper.fetchState(context: backgroundContext)
    }

    #expect(!state.noData)
    #expect(!state.needsLoad)
    #expect(state.canSkip)
  }

  @Test
  func needsLoadWhenNASRCycleHasExpired() throws {
    let container = try makeContainer()

    let (airport, runways) = AirportBuilder.KSQL.build()
    container.mainContext.insert(airport)
    for runway in runways { container.mainContext.insert(runway) }
    container.mainContext.insert(
      Cycle(
        dataSource: .nasr,
        name: "2401",
        effective: Date.now.addingTimeInterval(-172_800),
        expires: Date.now.addingTimeInterval(-86_400)
      )
    )
    try container.mainContext.save()

    let backgroundContext = ModelContext(container)
    let state = try withSchemaVersion(latestSchemaVersion) {
      try NavDataStateHelper.fetchState(context: backgroundContext)
    }

    #expect(!state.noData)
    #expect(state.needsLoad)
    #expect(state.canSkip)
  }

  @Test
  func staleSchemaVersionForcesReloadAndBlocksSkipping() throws {
    let container = try makeContainer()

    let (airport, runways) = AirportBuilder.KSQL.build()
    container.mainContext.insert(airport)
    for runway in runways { container.mainContext.insert(runway) }
    container.mainContext.insert(
      Cycle(
        dataSource: .nasr,
        name: "2501",
        effective: Date.now.addingTimeInterval(-86_400),
        expires: Date.now.addingTimeInterval(86_400)
      )
    )
    try container.mainContext.save()

    let backgroundContext = ModelContext(container)
    let state = try withSchemaVersion(latestSchemaVersion - 1) {
      try NavDataStateHelper.fetchState(context: backgroundContext)
    }

    #expect(!state.noData)
    #expect(state.needsLoad)
    #expect(!state.canSkip)
  }
}
