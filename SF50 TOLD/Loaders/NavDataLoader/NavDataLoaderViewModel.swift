import Defaults
import Observation
import SF50_Shared
import Sentry
import SwiftData

/// View model coordinating navigation data loading and UI state.
///
/// ``NavDataLoaderViewModel`` manages the decision logic for when to show the
/// data loader UI and coordinates the actual loading process via ``NavDataLoader``.
///
/// ## Loading Decision
///
/// The ``showLoader`` property determines whether to present the loading UI:
/// - `true` when no data exists or data is out of date (and not deferred)
/// - `false` when data is current or user chose to defer
///
/// ## Usage
///
/// ```swift
/// @State private var loaderVM = NavDataLoaderViewModel(container: container)
///
/// if loaderVM.showLoader {
///     DataLoaderView(viewModel: loaderVM)
/// }
/// ```
@Observable
@MainActor
final class NavDataLoaderViewModel: WithIdentifiableError {
  private(set) var state: NavDataLoader.State = .idle
  var error: Swift.Error?

  private(set) var noData = false
  private(set) var needsLoad = true
  private(set) var canSkip = false
  private(set) var networkIsExpensive = false
  private(set) var deferred = false

  private let container: ModelContainer
  private var cancellables: Set<Task<Void, Never>> = []

  var showLoader: Bool {
    (noData || needsLoad) && !deferred
  }

  /// Whether a fresh import may start, so a second tap cannot spawn a
  /// concurrent importer on the same store.
  private var canStartLoad: Bool {
    switch state {
      case .idle, .finished: true
      default: false
    }
  }

  init(container: ModelContainer) {
    self.container = container
    setupObservation()
  }

  /// Builds the importer's loader away from the main actor.
  ///
  /// Opening the importer's container brings up a second persistent store
  /// coordinator, which touches the filesystem, so it runs on the concurrent
  /// pool rather than on the main thread at the moment the user taps Load.
  @concurrent
  nonisolated private static func makeImportLoader(
    matching container: ModelContainer
  ) async throws -> NavDataLoader {
    NavDataLoader(modelContainer: try makeImportContainer(matching: container))
  }

  /// Creates a standalone container on the same store for the importer.
  ///
  /// The importer's bulk transactions then queue on their own persistent store
  /// coordinator, so main-context work (`@Query` fetches, model faults, history
  /// merges) never waits behind them — with WAL journaling, readers on another
  /// coordinator are not blocked by an in-flight write transaction.
  nonisolated private static func makeImportContainer(
    matching container: ModelContainer
  ) throws -> ModelContainer {
    // In-memory stores (used by UI tests) cannot be shared between containers.
    guard !container.configurations.contains(where: \.isStoredInMemoryOnly) else {
      return container
    }
    return try ModelContainer(
      for: container.schema,
      configurations: Array(container.configurations)
    )
  }

  private func setupObservation() {
    addTask(schemaVersionObservationTask())
    addTask(statePollingTask())
  }

  private func schemaVersionObservationTask() -> Task<Void, Never> {
    Task { [weak self] in
      for await _ in Defaults.updates(.schemaVersion)
      where !Task.isCancelled {
        guard let self else { return }
        await refreshState(fingerprint: "recalculate")
      }
    }
  }

  private func statePollingTask() -> Task<Void, Never> {
    Task { [weak self] in
      // Resolve the loader state at launch, then keep polling only while the
      // loader is still needed (no data yet, or a download in progress). Once
      // data is present and current the loader is dismissed and the poll
      // stops, so it never contends with the main context's SwiftData access
      // for the lifetime of the app — the dominant contributor to the
      // launch-time main-thread hangs. The schema-version observer revives
      // state when a reload becomes necessary.
      while !Task.isCancelled {
        guard let self else { return }
        await refreshState(fingerprint: "airportCheck")
        guard showLoader else { return }
        try? await Task.sleep(for: .seconds(0.5))
      }
    }
  }

  /// Reads the nav-data loader state on a background context, then applies it on
  /// the main actor — keeping launch-time SwiftData work off the main context.
  @concurrent
  private func refreshState(fingerprint: String) async {
    do {
      let context = ModelContext(container)
      let state = try NavDataStateHelper.fetchState(context: context)
      await applyState(state)
    } catch {
      await recordError(error, fingerprint: fingerprint)
    }
  }

  private func addTask(_ task: Task<Void, Never>) {
    cancellables.insert(task)
  }

  func load() {
    guard canStartLoad else { return }

    // Block re-entry and switch to the progress UI before the actor reports
    state = .downloading(progress: nil)

    addTask(Task { await runLoad() })
  }

  func loadLater() {
    if canSkip { deferred = true }
  }

  private func runLoad() async {
    guard let loader = await makeLoader() else { return }
    let progressTask = await observeProgress(of: loader)
    addTask(progressTask)
    await performLoad(with: loader, progressTask: progressTask)
  }

  private func makeLoader() async -> NavDataLoader? {
    do {
      return try await Self.makeImportLoader(matching: container)
    } catch {
      SentrySDK.capture(error: error) { scope in
        scope.setTag(value: "importContainer", key: "navData.operation")
        scope.setFingerprint(["navData", "importContainer"])
      }
      self.error = error

      // Return to the consent screen so the user can retry
      state = .idle
      return nil
    }
  }

  /// Mirrors the loader's pushed state onto the main actor for the progress UI.
  ///
  /// The loader yields into an `AsyncStream`, so following its progress never
  /// enqueues a job onto the loader's executor — an enqueue would block the main
  /// thread for as long as the import occupies that executor.
  private func observeProgress(of loader: NavDataLoader) async -> Task<Void, Never> {
    let updates = await loader.stateUpdates()
    return Task { [weak self] in
      for await loaderState in updates where !Task.isCancelled {
        guard let self else { return }

        // The actor hasn't begun loading; don't regress the UI to consent
        if case .idle = loaderState { continue }
        state = loaderState
      }
    }
  }

  private func performLoad(with loader: NavDataLoader, progressTask: Task<Void, Never>) async {
    let transaction = SentrySDK.startTransaction(
      name: "Nav Data Load",
      operation: "navData.load"
    )
    defer { progressTask.cancel() }
    do {
      error = nil
      try await loader.clearCycles()
      Defaults[.ourAirportsLastUpdated] = nil
      let result = try await loader.load()
      state = .finished

      Defaults[.ourAirportsLastUpdated] = result.ourAirportsLastUpdated
      Defaults[.schemaVersion] = latestSchemaVersion
      transaction.finish()
    } catch {
      transaction.finish(status: .internalError)
      SentrySDK.capture(error: error) { scope in
        scope.setTag(value: "load", key: "navData.operation")
        scope.setFingerprint(["navData", "load"])
      }
      self.error = error

      // Return to the consent screen so the user can retry the download
      progressTask.cancel()
      state = .idle
    }
  }

  private func applyState(_ state: NavDataStateHelper.State) {
    if noData != state.noData { self.noData = state.noData }
    if needsLoad != state.needsLoad { self.needsLoad = state.needsLoad }
    if canSkip != state.canSkip { self.canSkip = state.canSkip }
  }

  private func recordError(_ error: Swift.Error, fingerprint: String) {
    SentrySDK.capture(error: error) { scope in
      scope.setFingerprint(["navData", fingerprint])
    }
    self.error = error
  }
}

/// File-scope helper for computing nav-data loader state from any `ModelContext`.
///
/// Declared outside `NavDataLoaderViewModel` so it is nonisolated by default
/// and callable from both MainActor and background tasks without annotations.
private enum NavDataStateHelper {
  static func fetchState(context: ModelContext) throws -> State {
    var airportDescriptor = FetchDescriptor<SF50_Shared.Airport>()
    airportDescriptor.fetchLimit = 1
    let noData = try context.fetch(airportDescriptor).isEmpty

    let schemaOutOfDate = Defaults[.schemaVersion] != latestSchemaVersion
    let nasrExpiration = try fetchNASRExpiration(context: context)
    let dataOutOfDate = nasrExpiration.map { Date() > $0 } ?? true

    return State(
      noData: noData,
      needsLoad: schemaOutOfDate || dataOutOfDate,
      canSkip: !noData && !schemaOutOfDate
    )
  }

  private static func fetchNASRExpiration(context: ModelContext) throws -> Date? {
    let nasrRawValue = CycleDataSource.nasr.rawValue
    var descriptor = FetchDescriptor<Cycle>(
      predicate: #Predicate { $0._dataSource == nasrRawValue }
    )
    descriptor.fetchLimit = 1
    return try context.fetch(descriptor).first?.expires
  }

  struct State {
    let noData: Bool
    let needsLoad: Bool
    let canSkip: Bool
  }
}
