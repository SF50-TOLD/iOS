import BackgroundTasks
import Defaults
import Observation
import SF50_Shared
import Sentry
import SwiftData

/// View model coordinating navigation data loading and UI state.
///
/// ``NavDataLoaderViewModel`` manages the decision logic for when to show the
/// data loader UI, and starts or follows an update through ``NavDataUpdater``.
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

  var error: (any Swift.Error)?

  private(set) var noData = false
  private(set) var needsLoad = true
  private(set) var canSkip = false
  private(set) var networkIsExpensive = false
  private(set) var deferred = false

  private let container: ModelContainer

  /// The observers that keep the loader's state true for as long as this view model exists.
  ///
  /// Kept apart from the load, because abandoning a load must not also tear down the observers that
  /// decide when the loader is needed again.
  private var observations: Set<Task<Void, Never>> = []

  /// The load the pilot started, from the tap until it settles.
  private var loadTask: Task<Void, Never>?

  /// The progress of the update, as the loader screen shows it.
  ///
  /// A load the pilot has just asked for reads as downloading from the tap, before the system has
  /// let the work begin; an update the system started in the background reads as whatever it is
  /// doing, so a pilot who opens the app partway through one watches it finish.
  var state: NavDataLoader.State {
    if loadTask != nil, case .idle = NavDataUpdater.shared.state {
      return .downloading(progress: nil)
    }
    return NavDataUpdater.shared.state
  }

  var showLoader: Bool {
    (noData || needsLoad) && !deferred
  }

  /// Whether a load may start: not while one is already under way, from this screen or from the
  /// background.
  private var canStartLoad: Bool {
    guard loadTask == nil else { return false }
    switch state {
      case .idle, .finished: return true
      default: return false
    }
  }

  init(container: ModelContainer) {
    self.container = container
    setupObservation()
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

  func load() {
    guard canStartLoad else { return }
    loadTask = Task { [weak self] in
      await self?.runLoad()
      self?.loadTask = nil
    }
  }

  func loadLater() {
    if canSkip { deferred = true }
  }

  private func runLoad() async {
    error = nil

    // Ask the system to let this keep running if the pilot leaves the app. Safe now that an update
    // writes a generation nothing reads: a task the system cancels costs a file, not a database.
    let backgroundTask = await NavDataDownloadTask.shared.begin(
      title: String(localized: "Updating Navigation Data"),
      subtitle: String(localized: "Downloading")
    )
    backgroundTask?.expirationHandler = {
      MainActor.assumeIsolated { NavDataUpdater.shared.cancel() }
    }
    let reporting = backgroundTask.map(reportProgress(to:))

    var succeeded = false
    do {
      try await NavDataUpdater.shared.update(container: container, networkAccess: .any)
      succeeded = true
    } catch is CancellationError {
      // A load the system stopped finished nothing, and there is nothing to tell the pilot: the
      // dataset in use is the one they already had.
    } catch {
      self.error = error
    }

    reporting?.cancel()
    if succeeded { report(.finished, to: backgroundTask) }
    backgroundTask?.setTaskCompleted(success: succeeded)
  }

  /// Follows the update's phase and progress onto the system's own display of the work, for as long
  /// as it runs.
  private func reportProgress(to backgroundTask: BGContinuedProcessingTask) -> Task<Void, Never> {
    backgroundTask.progress.totalUnitCount = Self.progressUnits
    return Task { [weak self] in
      for await state in Observations({ NavDataUpdater.shared.state }) {
        if Task.isCancelled { break }
        self?.report(state, to: backgroundTask)
      }
    }
  }

  /// Mirrors the update's phase and progress onto the system's own display of the work.
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
    loadTask?.cancel()
  }
}

/// Computes whether nav data is missing or out of date, from any `ModelContext`.
///
/// Declared outside `NavDataLoaderViewModel` so it is nonisolated by default and callable from the
/// loader screen and from the background refresh alike.
enum NavDataStateHelper {
  static func fetchState(context: ModelContext) throws -> State {
    var airportDescriptor = FetchDescriptor<SF50_Shared.Airport>()
    airportDescriptor.fetchLimit = 1
    let noData = try context.fetch(airportDescriptor).isEmpty

    // The cycle judges itself, on the same half-open window a published manifest states: in force
    // from the instant it takes effect until the instant it expires, which is the instant its
    // successor takes effect. Anything else installed — a cycle that has lapsed, one dated ahead of
    // today, or no cycle at all — is data outside its validity, and the loader is what replaces it.
    let cycle = try installedNASRCycle(context: context)
    let schemaOutOfDate = Defaults[.schemaVersion] != latestSchemaVersion
    let dataOutOfDate = !(cycle?.isEffective ?? false)

    return State(
      noData: noData,
      needsLoad: schemaOutOfDate || dataOutOfDate,
      canSkip: !noData && !schemaOutOfDate,
      nasrCycleExpires: cycle?.expires
    )
  }

  /// The NASR cycle the installed dataset was built from, if there is one.
  private static func installedNASRCycle(context: ModelContext) throws -> Cycle? {
    let nasrRawValue = CycleDataSource.nasr.rawValue
    var descriptor = FetchDescriptor<Cycle>(
      predicate: #Predicate { $0._dataSource == nasrRawValue }
    )
    descriptor.fetchLimit = 1
    return try context.fetch(descriptor).first
  }

  struct State {
    let noData: Bool
    let needsLoad: Bool
    let canSkip: Bool

    /// When the installed NASR cycle stops being in force, or `nil` when none is installed.
    let nasrCycleExpires: Date?
  }
}
