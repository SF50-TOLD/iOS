import Defaults
import Observation
import SF50_Shared
import Sentry
import SwiftData
import os

/// Downloads the current nav-data cycle and switches the app to it, one update at a time.
///
/// Two paths start an update: the pilot, from the loader screen, and the system, in a background
/// processing task once the installed cycle has lapsed. Both run the same work — a store built ahead
/// of time where one is published, the property-list import where it is not — and they must never
/// run it twice at once, since each reserves and installs a generation of the store. A caller that
/// arrives while an update is running joins it instead of starting a second, so a pilot who opens the
/// app partway through a background update watches that update finish.
///
/// Every update writes a generation nothing is reading and switches to it only once it is whole, so
/// one that fails or is stopped costs a file the next launch reclaims, and nothing else.
@MainActor
@Observable
final class NavDataUpdater {
  /// The one updater, shared by every path that starts an update.
  static let shared = NavDataUpdater()

  private static let logger = Logger(
    subsystem: "codes.tim.SF50-TOLD",
    category: "NavDataUpdater"
  )

  private static let installer = NavDataStoreInstaller(layout: .appGroup)

  /// The progress of the update in flight, or where the last one left off.
  private(set) var state: NavDataLoader.State = .idle

  @ObservationIgnored private var inFlight: Task<Void, any Error>?

  private init() {}

  /// Builds the importer's loader away from the main actor.
  ///
  /// Opening the importer's container brings up a second persistent store coordinator, which touches
  /// the filesystem, so it runs on the concurrent pool rather than on the main thread.
  @concurrent
  nonisolated private static func makeImportLoader(
    matching container: ModelContainer,
    generation: Int,
    networkAccess: NavDataNetworkAccess
  ) async throws -> NavDataLoader {
    NavDataLoader(
      modelContainer: try makeImportContainer(matching: container, generation: generation),
      networkAccess: networkAccess
    )
  }

  /// Creates a writable container for the importer, on the generation it is about to write.
  ///
  /// The importer's bulk transactions queue on their own persistent store coordinator, so
  /// main-context work (`@Query` fetches, model faults, history merges) never waits behind them —
  /// with WAL journaling, readers on another coordinator are not blocked by an in-flight write.
  ///
  /// It writes a generation nothing is reading. The dataset in use is not touched at all, which is
  /// what makes an import safe to abandon: a failed one leaves a file nobody points at.
  nonisolated private static func makeImportContainer(
    matching container: ModelContainer,
    generation: Int
  ) throws -> ModelContainer {
    // In-memory stores (used by UI tests) cannot be shared between containers.
    guard !container.configurations.contains(where: \.isStoredInMemoryOnly) else {
      return container
    }
    return try AppStore.makeWritableContainer(layout: .appGroup, generation: generation)
  }

  /// The whole of what an error says.
  ///
  /// `localizedDescription` renders only a `LocalizedError`'s category, which is the same sentence
  /// for every case in it; the specifics are its reason.
  private static func wholeOf(_ error: any Swift.Error) -> String {
    [error.localizedDescription, (error as? any LocalizedError)?.failureReason]
      .compactMap(\.self)
      .joined(separator: " ")
  }

  /// Runs an update, or waits for the one already running to finish.
  ///
  /// A caller that joins a running update does not choose its network policy: the update keeps the
  /// one it started with.
  ///
  /// - Parameters:
  ///   - container: The container the app reads its stores through.
  ///   - networkAccess: The networks the update's downloads may use.
  /// - Throws: `CancellationError` when the update was stopped before it finished, and otherwise
  ///   whatever stopped the import. A store built ahead of time that cannot be installed is not an
  ///   error: the import runs in its place.
  func update(container: ModelContainer, networkAccess: NavDataNetworkAccess) async throws {
    if let inFlight {
      try await inFlight.value
      return
    }

    let update = Task { try await perform(container: container, networkAccess: networkAccess) }
    inFlight = update
    defer { inFlight = nil }
    try await withTaskCancellationHandler {
      try await update.value
    } onCancel: {
      update.cancel()
    }
  }

  /// Stops the update in flight, if there is one.
  func cancel() {
    inFlight?.cancel()
  }

  private func perform(container: ModelContainer, networkAccess: NavDataNetworkAccess) async throws
  {
    state = .downloading(progress: nil)
    let generation = Self.installer.reserveGeneration()

    do {
      // A store built ahead of time turns minutes of assembling the database into a download. It is
      // an optimization, not a dependency: anything that goes wrong falls back to importing the
      // property list, which is still published and still works.
      if await installPrebuiltStore(
        generation: generation,
        container: container,
        networkAccess: networkAccess
      ) {
        return
      }

      // The prebuilt path reports a cancellation the same way it reports a cycle that was never
      // published, so ask directly.
      try Task.checkCancellation()

      try await importPropertyList(
        generation: generation,
        container: container,
        networkAccess: networkAccess
      )
    } catch {
      state = .idle
      throw error
    }
  }

  /// Downloads and installs a store that was built ahead of time.
  ///
  /// - Returns: Whether the app is now running on a prebuilt store.
  private func installPrebuiltStore(
    generation: Int,
    container: ModelContainer,
    networkAccess: NavDataNetworkAccess
  ) async -> Bool {
    let (updates, continuation) = AsyncStream<NavDataLoader.State>.makeStream(
      of: NavDataLoader.State.self,
      bufferingPolicy: .bufferingNewest(1)
    )
    let mirror = Task { [weak self] in
      for await update in updates {
        if Task.isCancelled { break }
        self?.state = update
      }
    }
    defer { mirror.cancel() }

    do {
      let manifest = try await PrebuiltNavDataStore(networkAccess: networkAccess).download(
        to: StoreLayout.appGroup.navStoreURL(generation: generation),
        reportingTo: continuation
      )
      continuation.finish()
      try Self.install(generation: generation, container: container)
      Defaults[.ourAirportsLastUpdated] = manifest.ourAirportsLastUpdated
      Defaults[.schemaVersion] = latestSchemaVersion
      state = .finished
      Self.logger.notice(
        "Installed the prebuilt store for cycle \(manifest.cycle, privacy: .public)"
      )
      return true
    } catch {
      continuation.finish()
      // What happens next is the caller's to decide: a cancelled update imports nothing.
      Self.logger.notice("Passed over the prebuilt store: \(Self.wholeOf(error), privacy: .public)")
      StoreLayout.removeStore(at: StoreLayout.appGroup.navStoreURL(generation: generation))
      return false
    }
  }

  private func importPropertyList(
    generation: Int,
    container: ModelContainer,
    networkAccess: NavDataNetworkAccess
  ) async throws {
    let loader = try await makeLoader(
      matching: container,
      generation: generation,
      networkAccess: networkAccess
    )

    let progress = await mirrorProgress(of: loader)
    defer { progress.cancel() }

    let transaction = SentrySDK.startTransaction(
      name: "Nav Data Load",
      operation: "navData.load"
    )
    do {
      let result = try await loader.load()
      try Self.install(generation: generation, container: container)
      Defaults[.ourAirportsLastUpdated] = result.ourAirportsLastUpdated
      Defaults[.schemaVersion] = latestSchemaVersion
      state = .finished
      transaction.finish()
    } catch {
      // A transfer the system stopped fails the same way a broken one does, and so does one this
      // update's network policy refused. Neither the pilot nor Sentry needs to hear about either.
      if Task.isCancelled {
        transaction.finish(status: .cancelled)
        throw CancellationError()
      }
      if NavDataNetworkAccess.isRefusal(error) {
        transaction.finish(status: .unavailable)
        throw error
      }

      transaction.finish(status: .internalError)
      SentrySDK.capture(error: error) { scope in
        scope.setTag(value: "load", key: "navData.operation")
        scope.setFingerprint(["navData", "load"])
      }
      throw error
    }
  }

  private func makeLoader(
    matching container: ModelContainer,
    generation: Int,
    networkAccess: NavDataNetworkAccess
  ) async throws -> NavDataLoader {
    do {
      return try await Self.makeImportLoader(
        matching: container,
        generation: generation,
        networkAccess: networkAccess
      )
    } catch {
      SentrySDK.capture(error: error) { scope in
        scope.setTag(value: "importContainer", key: "navData.operation")
        scope.setFingerprint(["navData", "importContainer"])
      }
      throw error
    }
  }

  /// Mirrors the loader's pushed state onto the main actor.
  ///
  /// The loader yields into an `AsyncStream`, so following its progress never enqueues a job onto
  /// the loader's executor — an enqueue would block the main thread for as long as the import
  /// occupies that executor.
  private func mirrorProgress(of loader: NavDataLoader) async -> Task<Void, Never> {
    let updates = await loader.stateUpdates()
    return Task { [weak self] in
      for await loaderState in updates {
        if Task.isCancelled { break }

        // The loader hasn't begun; don't regress the update to idle.
        if case .idle = loaderState { continue }
        self?.state = loaderState
      }
    }
  }
}

// MARK: - Installing a generation

extension NavDataUpdater {
  /// Switches to the generation just imported.
  ///
  /// The switch is a single recorded number, made only after the new store has been opened and
  /// found to hold airports. Until that point the dataset in use has not been touched, so a failure
  /// here — or a process killed mid-import — costs the pilot nothing.
  private static func install(generation: Int, container: ModelContainer) throws {
    try installer.install(generation: generation)
    clearNOTAMs(in: container)
    clearSelectionsMissing(fromGeneration: generation, container: container)
    // The app watches the active generation and reopens its own store; doing it here as well would
    // race that, and leave the container the views hold pointing at the older file.
  }

  /// Forgets a selected airport the incoming dataset no longer carries, and the runway chosen on
  /// it.
  ///
  /// The FAA retires airports between cycles, and occasionally corrects the site number that
  /// identifies one, so a selection made under an earlier dataset can name a record the new one
  /// does not hold. Left in place it resolves to nothing in the widget and in Siri, which report a
  /// missing airport and suggest reloading the very data that removed it.
  ///
  /// Internal so a test can run the check against a generation on disk without downloading one.
  ///
  /// - Parameters:
  ///   - generation: The generation being installed.
  ///   - container: The container the app reads its stores through.
  static func clearSelectionsMissing(fromGeneration generation: Int, container: ModelContainer) {
    guard let context = navDataContext(forGeneration: generation, container: container) else {
      return
    }
    for operation in Operation.allCases {
      guard let recordID = operation.selectedAirportRecordID,
        airportIsMissing(recordID, from: context)
      else { continue }
      operation.clearSelection()
      logger.notice(
        "Cleared the \(operation.rawValue, privacy: .public) airport, absent from the new dataset"
      )
    }
  }

  /// Whether the dataset lacks the airport a selection names. A failed fetch reads as present, so
  /// nothing is cleared on the strength of an error.
  private static func airportIsMissing(_ recordID: String, from context: ModelContext) -> Bool {
    do { return try findAirport(for: recordID, in: context) == nil } catch { return false }
  }

  /// A context on the generation just installed, or `nil` when that generation cannot be read.
  ///
  /// The container the views hold still reads the previous generation here, so this check opens the
  /// new one itself — and opens it as a generation that must already be on disk. A generation
  /// another process has swept out from under the install would otherwise be bootstrapped into an
  /// empty store, which answers that it carries no airports and costs the pilot both selections.
  ///
  /// In-memory stores cannot be shared between containers, so tests and previews read the container
  /// they were given.
  private static func navDataContext(
    forGeneration generation: Int,
    container: ModelContainer
  ) -> ModelContext? {
    guard !container.configurations.contains(where: \.isStoredInMemoryOnly) else {
      return ModelContext(container)
    }
    do {
      return ModelContext(
        try AppStore.makeContainerForExistingGeneration(layout: .appGroup, generation: generation)
      )
    } catch {
      logger.error(
        """
        Kept the airport selections; couldn’t read generation \(generation, privacy: .public): \
        \(wholeOf(error), privacy: .public)
        """
      )
      return nil
    }
  }

  /// Discards the NOTAMs the pilot entered against the dataset just replaced.
  ///
  /// A NOTAM carries no effective time, so one written against a previous cycle would otherwise
  /// keep asserting a contamination or a closure that nothing has re-confirmed.
  private static func clearNOTAMs(in container: ModelContainer) {
    let context = ModelContext(container)
    try? NOTAMStore(context: context).removeAll()
    try? context.save()
  }
}
