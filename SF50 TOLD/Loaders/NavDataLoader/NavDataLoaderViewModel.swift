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

  init(container: ModelContainer) {
    self.container = container
    do {
      try recalculate()
    } catch {
      SentrySDK.capture(error: error) { scope in
        scope.setFingerprint(["navData", "recalculate"])
      }
      self.error = error
    }

    setupObservation()
  }

  private func setupObservation() {
    addTask(
      Task {
        for await _ in Defaults.updates(.schemaVersion)
        where !Task.isCancelled {
          do {
            try recalculate()
          } catch {
            SentrySDK.capture(error: error) { scope in
              scope.setFingerprint(["navData", "recalculate"])
            }
            self.error = error
          }
        }
      }
    )

    addTask(
      Task.detached { [container] in
        do {
          let context = ModelContext(container)
          while !Task.isCancelled {
            let state = try NavDataStateHelper.fetchState(context: context)
            await MainActor.run {
              self.applyState(state)
            }
            try? await Task.sleep(for: .seconds(0.5))
          }
        } catch {
          await MainActor.run {
            SentrySDK.capture(error: error) { scope in
              scope.setFingerprint(["navData", "airportCheck"])
            }
            self.error = error
          }
        }
      }
    )
  }

  private func addTask(_ task: Task<Void, Never>) {
    cancellables.insert(task)
  }

  func load() {
    let loader = NavDataLoader(modelContainer: container)

    addTask(
      Task {
        let transaction = SentrySDK.startTransaction(
          name: "Nav Data Load",
          operation: "navData.load"
        )
        do {
          error = nil
          try clearCycles()
          let result = try await loader.load()

          await MainActor.run {
            let context = container.mainContext
            if let nasr = result.cycles.nasr {
              context.insert(
                Cycle(
                  dataSource: .nasr,
                  name: nasr.name,
                  effective: nasr.effective,
                  expires: nasr.expires
                )
              )
            }
            if let cifp = result.cycles.cifp {
              context.insert(
                Cycle(
                  dataSource: .cifp,
                  name: cifp.name,
                  effective: cifp.effective,
                  expires: cifp.expires
                )
              )
            }
            if let dof = result.cycles.dof {
              context.insert(
                Cycle(
                  dataSource: .dof,
                  name: dof.name,
                  effective: dof.effective,
                  expires: dof.expires
                )
              )
            }
            try? context.save()
            try? self.recalculate()
            Defaults[.ourAirportsLastUpdated] = result.ourAirportsLastUpdated
            Defaults[.schemaVersion] = latestSchemaVersion
          }
          transaction.finish()
        } catch {
          transaction.finish(status: .internalError)
          SentrySDK.capture(error: error) { scope in
            scope.setTag(value: "load", key: "navData.operation")
            scope.setFingerprint(["navData", "load"])
          }
          self.error = error
        }
      }
    )

    addTask(
      Task { [weak self] in
        while !Task.isCancelled {
          let state = await loader.state
          self?.state = state
          try? await Task.sleep(for: .seconds(0.25))
        }
      }
    )
  }

  func loadLater() {
    if canSkip { deferred = true }
  }

  private func clearCycles() throws {
    let context = container.mainContext
    try context.delete(model: Cycle.self)
    try context.save()
    Defaults[.ourAirportsLastUpdated] = nil
  }

  private func recalculate() throws {
    let state = try NavDataStateHelper.fetchState(context: container.mainContext)
    applyState(state)
  }

  private func applyState(_ state: NavDataStateHelper.State) {
    if noData != state.noData { self.noData = state.noData }
    if needsLoad != state.needsLoad { self.needsLoad = state.needsLoad }
    if canSkip != state.canSkip { self.canSkip = state.canSkip }
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
