import BackgroundTasks
import Defaults
import os
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
  /// The scale the loader's 0…1 progress is reported to the system on.
  private static let progressUnits: Int64 = 100

  private(set) var state: NavDataLoader.State = .idle
  var error: (any Swift.Error)?

  private(set) var noData = false
  private(set) var needsLoad = true
  private(set) var canSkip = false
  private(set) var networkIsExpensive = false
  private(set) var deferred = false

  private let logger = Logger(
    subsystem: "codes.tim.SF50-TOLD",
    category: "NavDataLoaderViewModel"
  )

  private let container: ModelContainer
  private let installer = NavDataStoreInstaller(layout: .appGroup)

  /// The observers that keep the loader's state true for as long as this view model exists.
  ///
  /// Kept apart from the tasks doing a load, because abandoning a load must not also tear down the
  /// observers that decide when the loader is needed again.
  private var observations: Set<Task<Void, Never>> = []

  /// The tasks belonging to the load in progress, cancelled together when one is abandoned.
  private var loadTasks: Set<Task<Void, Never>> = []

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
    matching container: ModelContainer,
    generation: Int
  ) async throws -> NavDataLoader {
    NavDataLoader(
      modelContainer: try makeImportContainer(matching: container, generation: generation)
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

  private func setupObservation() {
    observations.insert(schemaVersionObservationTask())
    observations.insert(statePollingTask())
  }

  private func schemaVersionObservationTask() -> Task<Void, Never> {
    Task { [weak self] in
      for await _ in Defaults.updates(.schemaVersion) {
        if Task.isCancelled { break }
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

  private func addLoadTask(_ task: Task<Void, Never>) {
    loadTasks.insert(task)
  }

  func load() {
    guard canStartLoad else { return }

    // Block re-entry and switch to the progress UI before the actor reports
    state = .downloading(progress: nil)

    addLoadTask(Task { await runLoad() })
  }

  func loadLater() {
    if canSkip { deferred = true }
  }

  private func runLoad() async {
    error = nil
    let generation = installer.reserveGeneration()

    // Ask the system to let this keep running if the pilot leaves the app. Safe now that an import
    // writes a generation nothing reads: a task the system cancels costs a file, not a database.
    let backgroundTask = await NavDataDownloadTask.shared.begin(
      title: String(localized: "Updating Navigation Data"),
      subtitle: String(localized: "Downloading")
    )
    backgroundTask?.expirationHandler = { [weak self] in
      MainActor.assumeIsolated { self?.cancelLoad() }
    }
    // A load the system stopped finished nothing, whether or not it left an error behind: the
    // dataset in use is the one the pilot already had.
    defer { backgroundTask?.setTaskCompleted(success: error == nil && !Task.isCancelled) }

    // A store built ahead of time turns minutes of assembling the database into a download. It is
    // an optimization, not a dependency: anything that goes wrong falls back to importing the
    // property list, which is still published and still works.
    if await installPrebuiltStore(generation: generation, reportingTo: backgroundTask) { return }

    // The prebuilt path reports a cancellation the same way it reports a cycle that was never
    // published, so ask directly. Starting the import here would raise an error alert at a pilot
    // who did nothing but leave the app.
    guard !Task.isCancelled else { return }

    await importPropertyList(generation: generation, reportingTo: backgroundTask)
  }

  /// Downloads and installs a store that was built ahead of time.
  ///
  /// - Returns: Whether the app is now running on a prebuilt store.
  private func installPrebuiltStore(
    generation: Int,
    reportingTo backgroundTask: BGContinuedProcessingTask?
  ) async -> Bool {
    let (updates, continuation) = AsyncStream<NavDataLoader.State>.makeStream(
      of: NavDataLoader.State.self,
      bufferingPolicy: .bufferingNewest(1)
    )
    backgroundTask?.progress.totalUnitCount = Self.progressUnits
    let mirror = Task { [weak self] in
      for await update in updates {
        if Task.isCancelled { break }
        guard let self else { return }
        state = update
        report(update, to: backgroundTask)
      }
    }
    addLoadTask(mirror)
    defer { mirror.cancel() }

    do {
      let manifest = try await PrebuiltNavDataStore().download(
        to: StoreLayout.appGroup.navStoreURL(generation: generation),
        reportingTo: continuation
      )
      continuation.finish()
      try install(generation: generation)
      Defaults[.ourAirportsLastUpdated] = manifest.ourAirportsLastUpdated
      Defaults[.schemaVersion] = latestSchemaVersion
      finish(reportingTo: backgroundTask)
      logger.notice("Installed the prebuilt store for cycle \(manifest.cycle, privacy: .public)")
      return true
    } catch {
      continuation.finish()
      // `localizedDescription` renders only a `LocalizedError`'s category, which is the same
      // sentence for every reason a prebuilt store was passed over; the specifics are its reason.
      let cause = [error.localizedDescription, (error as? any LocalizedError)?.failureReason]
        .compactMap(\.self)
        .joined(separator: " ")
      // What happens next is the caller's to decide: a cancelled load imports nothing.
      logger.notice("Passed over the prebuilt store: \(cause, privacy: .public)")
      StoreLayout.removeStore(at: StoreLayout.appGroup.navStoreURL(generation: generation))
      return false
    }
  }

  private func importPropertyList(
    generation: Int,
    reportingTo backgroundTask: BGContinuedProcessingTask?
  ) async {
    guard let loader = await makeLoader(generation: generation) else { return }

    let progressTask = await observeProgress(of: loader, reportingTo: backgroundTask)
    addLoadTask(progressTask)
    await performLoad(
      with: loader,
      generation: generation,
      progressTask: progressTask,
      reportingTo: backgroundTask
    )
  }

  /// Abandons an import the system has asked to stop.
  ///
  /// The generation being written is left where it is; nothing points at it, and the next launch
  /// reclaims it. The dataset in use was never touched.
  ///
  /// Only the load's own tasks stop. The observers that decide when the loader is needed keep
  /// running, so the next launch — or the next schema change — still finds its way back here.
  private func cancelLoad() {
    for task in loadTasks { task.cancel() }
    loadTasks.removeAll()
    state = .idle
  }

  /// Records a completed load, and tells the system's own display of the work that it is done.
  ///
  /// The system reads the title, subtitle, and progress it was last given until the moment the task
  /// completes, so a load that never reports its last phase is shown mid-download as it finishes.
  private func finish(reportingTo backgroundTask: BGContinuedProcessingTask?) {
    state = .finished
    report(.finished, to: backgroundTask)
  }

  private func makeLoader(generation: Int) async -> NavDataLoader? {
    do {
      return try await Self.makeImportLoader(matching: container, generation: generation)
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
  private func observeProgress(
    of loader: NavDataLoader,
    reportingTo backgroundTask: BGContinuedProcessingTask?
  ) async -> Task<Void, Never> {
    let updates = await loader.stateUpdates()
    backgroundTask?.progress.totalUnitCount = Self.progressUnits
    return Task { [weak self] in
      for await loaderState in updates {
        if Task.isCancelled { break }
        guard let self else { return }

        // The actor hasn't begun loading; don't regress the UI to consent
        if case .idle = loaderState { continue }
        state = loaderState
        report(loaderState, to: backgroundTask)
      }
    }
  }

  /// Mirrors the loader's phase and progress onto the system's own display of the work.
  ///
  /// A continued-processing task must report progress: one the system reads as stalled is expired
  /// to reclaim its resources.
  private func report(_ state: NavDataLoader.State, to backgroundTask: BGContinuedProcessingTask?) {
    guard let backgroundTask else { return }

    let (subtitle, fraction): (String, Float?) =
      switch state {
        case .idle: (String(localized: "Starting"), 0)
        case .downloading(let progress): (String(localized: "Downloading"), progress)
        case .extracting(let progress): (String(localized: "Decompressing"), progress)
        case .loading(let progress): (String(localized: "Processing"), progress)
        case .finished: (String(localized: "Finished"), 1)
      }

    backgroundTask.updateTitle(String(localized: "Updating Navigation Data"), subtitle: subtitle)
    guard let fraction else { return }
    backgroundTask.progress.completedUnitCount = Int64(fraction * Float(Self.progressUnits))
  }

  private func performLoad(
    with loader: NavDataLoader,
    generation: Int,
    progressTask: Task<Void, Never>,
    reportingTo backgroundTask: BGContinuedProcessingTask?
  ) async {
    let transaction = SentrySDK.startTransaction(
      name: "Nav Data Load",
      operation: "navData.load"
    )
    defer { progressTask.cancel() }
    do {
      Defaults[.ourAirportsLastUpdated] = nil
      let result = try await loader.load()
      try install(generation: generation)
      finish(reportingTo: backgroundTask)

      Defaults[.ourAirportsLastUpdated] = result.ourAirportsLastUpdated
      Defaults[.schemaVersion] = latestSchemaVersion
      transaction.finish()
    } catch {
      // Return to the consent screen so the user can retry the download
      progressTask.cancel()
      state = .idle

      // A cancelled transfer fails the same way a broken one does. Neither the pilot nor Sentry
      // needs to hear about work the system stopped because the app went to the background.
      guard !Task.isCancelled else {
        transaction.finish(status: .cancelled)
        return
      }

      transaction.finish(status: .internalError)
      SentrySDK.capture(error: error) { scope in
        scope.setTag(value: "load", key: "navData.operation")
        scope.setFingerprint(["navData", "load"])
      }
      self.error = error
    }
  }

  /// Switches to the generation just imported, and reopens the store against it.
  ///
  /// The switch is a single recorded number, made only after the new store has been opened and
  /// found to hold airports. Until that point the dataset in use has not been touched, so a failure
  /// here — or a process killed mid-import — costs the pilot nothing.
  private func install(generation: Int) throws {
    try installer.install(generation: generation)
    clearNOTAMs()
    // The app watches the active generation and reopens its own store; doing it here as well would
    // race that, and leave the container the views hold pointing at the older file.
  }

  /// Discards the NOTAMs the pilot entered against the dataset just replaced.
  ///
  /// A NOTAM carries no effective time, so one written against a previous cycle would otherwise
  /// keep asserting a contamination or a closure that nothing has re-confirmed.
  private func clearNOTAMs() {
    let context = ModelContext(container)
    try? NOTAMStore(context: context).removeAll()
    try? context.save()
  }

  private func applyState(_ state: NavDataStateHelper.State) {
    if noData != state.noData { self.noData = state.noData }
    if needsLoad != state.needsLoad { self.needsLoad = state.needsLoad }
    if canSkip != state.canSkip { self.canSkip = state.canSkip }
  }

  private func recordError(_ error: any Swift.Error, fingerprint: String) {
    SentrySDK.capture(error: error) { scope in
      scope.setFingerprint(["navData", fingerprint])
    }
    self.error = error
  }

  isolated deinit {
    for task in observations { task.cancel() }
    for task in loadTasks { task.cancel() }
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
    let dataOutOfDate = try !isNASRCycleEffective(context: context)

    return State(
      noData: noData,
      needsLoad: schemaOutOfDate || dataOutOfDate,
      canSkip: !noData && !schemaOutOfDate
    )
  }

  /// Whether the installed NASR cycle is inside the window it is effective for.
  ///
  /// The cycle judges itself, on the same half-open window a published manifest states: in force
  /// from the instant it takes effect until the instant it expires, which is the instant its
  /// successor takes effect. Anything else installed — a cycle that has lapsed, one dated ahead of
  /// today, or no cycle at all — is data outside its validity, and the loader is what replaces it.
  private static func isNASRCycleEffective(context: ModelContext) throws -> Bool {
    let nasrRawValue = CycleDataSource.nasr.rawValue
    var descriptor = FetchDescriptor<Cycle>(
      predicate: #Predicate { $0._dataSource == nasrRawValue }
    )
    descriptor.fetchLimit = 1
    return try context.fetch(descriptor).first?.isEffective ?? false
  }

  struct State {
    let noData: Bool
    let needsLoad: Bool
    let canSkip: Bool
  }
}
