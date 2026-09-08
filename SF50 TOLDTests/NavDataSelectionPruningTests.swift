import Defaults
import Foundation
import SF50_Shared
import SwiftData
import Testing

@testable import SF50_TOLD

/// A leg's airport is remembered in the app group as a record ID, and the FAA retires airports
/// between cycles. Installing a dataset that no longer carries one has to forget the selection,
/// while a dataset that still carries it must leave the selection alone — a prune that fired on
/// every install would cost the pilot the airport chosen for the flight.
///
/// The check opens the generation being installed rather than the container the views hold, so
/// these tests hand the view model a store on disk and write the incoming dataset where production
/// writes it. A view model given an in-memory store reads back the container it was handed, which
/// is not the path this behavior takes on a device.
@Suite(.serialized)
@MainActor
struct `Selection Pruning on Install` {
  private static let carriedAirport = "CARRIED", retiredAirport = "RETIRED",
    selectedRunway = "18"

  /// The generation the view model's own container reads: the dataset being replaced.
  private static let supersededGeneration = 1

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

  /// Selects an airport for each leg, writes a generation carrying only ``carriedAirport``, and
  /// runs `body` against a view model whose own container reads the dataset being replaced.
  ///
  /// The generation is written into the app group, since that is where an install looks for it. A
  /// process killed before the store is removed leaves one behind, which the next launch reclaims.
  ///
  /// `body` must not suspend. These tests are hosted by the app, whose performance view models
  /// observe these very defaults and forget an airport ID they cannot resolve in the store they
  /// hold — which neither of these IDs resolves in. Nothing of theirs can interleave while the
  /// body stays synchronous on the main actor.
  ///
  /// - Parameters:
  ///   - takeoff: The record ID selected for the takeoff leg.
  ///   - landing: The record ID selected for the landing leg.
  ///   - body: Runs with the view model and the generation being installed.
  private static func withInstalledGeneration(
    takeoff: String,
    landing: String,
    _ body: (NavDataLoaderViewModel, Int) throws -> Void
  ) throws {
    let selections = LegSelections.current(),
      generation = NavDataStoreInstaller(layout: .appGroup).reserveGeneration()
    defer {
      selections.restore()
      StoreLayout.removeStore(at: StoreLayout.appGroup.navStoreURL(generation: generation))
    }

    try write(carriedAirport, toGeneration: generation)
    Defaults[.takeoffAirport] = takeoff
    Defaults[.landingAirport] = landing
    Defaults[.takeoffRunway] = selectedRunway
    Defaults[.landingRunway] = selectedRunway

    let viewModel = NavDataLoaderViewModel(container: try supersededContainer())
    try body(viewModel, generation)
  }

  /// A temporary store standing in for the dataset the install is replacing.
  ///
  /// It holds a dataset that reads as current, so the view model's launch-state poll settles on
  /// its first pass rather than running for the rest of the test process. The store is left on
  /// disk for the same reason: that poll outlives the test, and one reading a store deleted
  /// underneath it turns into an error reported every half second.
  private static func supersededContainer() throws -> ModelContainer {
    let layout = StoreLayout(
      baseDirectory: FileManager.default.temporaryDirectory
        .appending(path: "SelectionPruningTests-\(UUID().uuidString)")
    )
    let context = ModelContext(
      try AppStore.makeWritableContainer(layout: layout, generation: supersededGeneration)
    )
    context.insert(airport(recordID: carriedAirport))
    context.insert(
      Cycle(dataSource: .nasr, name: "TEST", effective: .distantPast, expires: .distantFuture)
    )
    try context.save()
    return context.container
  }

  private static func write(_ recordID: String, toGeneration generation: Int) throws {
    let context = ModelContext(
      try AppStore.makeWritableContainer(layout: .appGroup, generation: generation)
    )
    context.insert(airport(recordID: recordID))
    try context.save()
  }

  @Test
  func `forgets a takeoff airport the incoming dataset dropped`() throws {
    try Self.withInstalledGeneration(
      takeoff: Self.retiredAirport,
      landing: Self.carriedAirport
    ) { viewModel, generation in
      viewModel.clearSelectionsMissing(fromGeneration: generation)

      #expect(Defaults[.takeoffAirport] == nil)
      #expect(Defaults[.takeoffRunway] == nil)
      #expect(Defaults[.landingAirport] == Self.carriedAirport)
      #expect(Defaults[.landingRunway] == Self.selectedRunway)
    }
  }

  @Test
  func `forgets a landing airport the incoming dataset dropped`() throws {
    try Self.withInstalledGeneration(
      takeoff: Self.carriedAirport,
      landing: Self.retiredAirport
    ) { viewModel, generation in
      viewModel.clearSelectionsMissing(fromGeneration: generation)

      #expect(Defaults[.landingAirport] == nil)
      #expect(Defaults[.landingRunway] == nil)
      #expect(Defaults[.takeoffAirport] == Self.carriedAirport)
      #expect(Defaults[.takeoffRunway] == Self.selectedRunway)
    }
  }

  @Test
  func `keeps a selection the incoming dataset still carries`() throws {
    try Self.withInstalledGeneration(
      takeoff: Self.carriedAirport,
      landing: Self.carriedAirport
    ) { viewModel, generation in
      viewModel.clearSelectionsMissing(fromGeneration: generation)

      #expect(Defaults[.takeoffAirport] == Self.carriedAirport)
      #expect(Defaults[.takeoffRunway] == Self.selectedRunway)
      #expect(Defaults[.landingAirport] == Self.carriedAirport)
      #expect(Defaults[.landingRunway] == Self.selectedRunway)
    }
  }

  /// The defaults a leg selection lives in, captured so one test's selections cannot reach
  /// another's.
  private struct LegSelections {
    let takeoffAirport, takeoffRunway, landingAirport, landingRunway: String?

    static func current() -> Self {
      .init(
        takeoffAirport: Defaults[.takeoffAirport],
        takeoffRunway: Defaults[.takeoffRunway],
        landingAirport: Defaults[.landingAirport],
        landingRunway: Defaults[.landingRunway]
      )
    }

    func restore() {
      Defaults[.takeoffAirport] = takeoffAirport
      Defaults[.takeoffRunway] = takeoffRunway
      Defaults[.landingAirport] = landingAirport
      Defaults[.landingRunway] = landingRunway
    }
  }
}
