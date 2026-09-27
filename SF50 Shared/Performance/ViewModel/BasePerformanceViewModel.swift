public import Defaults
public import Foundation
import Logging
import MeasurementKit
public import Observation
import Sentry
public import SwiftData

/// Abstract base class for performance view models.
///
/// ``BasePerformanceViewModel`` provides shared infrastructure for takeoff and landing
/// performance calculations, including:
///
/// - Input observation (airport, runway, weight, conditions)
/// - Model initialization based on user settings
/// - NOTAM fetching and caching
/// - Automatic recalculation when inputs change
///
/// ## Subclassing
///
/// Subclasses must override:
/// - ``airportDefaultsKey`` - Which airport setting to observe
/// - ``runwayDefaultsKey`` - Which runway setting to observe
/// - ``fuelDefaultsKey`` - Which fuel setting to observe
/// - ``recalculate()`` - Perform the actual performance calculation
///
/// ## Observation
///
/// The view model automatically observes changes to:
/// - Selected airport and runway (from Defaults)
/// - Weight components (empty weight, payload, fuel, density)
/// - Model settings (regression vs tabular, thrust schedule)
/// - Safety factor settings
///
/// ## NOTAM Support
///
/// Downloaded NOTAMs from the FAA API are available via ``downloadedNOTAMs``.
/// Call ``fetchNOTAMs(plannedTime:)`` to load NOTAMs for the current airport.
@Observable
@MainActor
open class BasePerformanceViewModel: WithIdentifiableError {
  // MARK: - Properties

  private static let logger = Logger(label: "codes.tim.SF50-TOLD.BasePerformanceViewModel")

  /// How long after a NOTAM expires it's still treated as current, as the NOTAM list does.
  private static let expiryWindowSeconds: TimeInterval = 3600

  private let container: ModelContainer

  private var notamStore: NOTAMStore { .init(context: container.mainContext) }
  private let notamLoader: any NOTAMLoaderProtocol
  private let notamProposer: NOTAMProposer
  internal var model: (any PerformanceModel)?
  private var cancellables: Set<Task<Void, Never>> = []
  private var notamObservationTask: Task<Void, Never>?
  private var notamReadingTask: Task<Void, Never>?
  internal let calculationService: any PerformanceCalculationService

  // MARK: - Inputs (to be overridden or used by subclasses)

  public var flapSetting: FlapSetting {
    didSet {
      model = initializeModel()
      Task { recalculate() }
    }
  }

  public private(set) var weight: Measurement<UnitMass> {
    didSet {
      model = initializeModel()
      Task { recalculate() }
    }
  }

  public private(set) var airport: Airport?

  public private(set) var runway: Runway? {
    didSet {
      notam = runway.flatMap { notamStore.upsert(for: $0) }
      notamProposal = nil
      model = initializeModel()
      Task { recalculate() }

      // Set up observation for NOTAM changes on this runway
      setupRunwayNOTAMObservation()
    }
  }

  /// The NOTAM restricting the selected runway.
  ///
  /// Resolved when the runway changes rather than followed through a relationship: a NOTAM names
  /// its runway, so that nav data can be replaced without taking the pilot's entries with it.
  ///
  /// A runway that has none yet gets an empty one, because the NOTAM editor binds to a model object
  /// and so needs one to exist before it opens. An empty NOTAM restricts nothing and counts for
  /// nothing on the badge.
  public private(set) var notam: NOTAM?

  public var conditions: Conditions {
    didSet {
      model = initializeModel()
      Task { recalculate() }
    }
  }

  public var error: (any Error)?

  // MARK: - Downloaded NOTAMs

  /// NOTAMs downloaded from the API for the current airport
  public private(set) var downloadedNOTAMs: [NOTAMResponse] = []

  /// Whether NOTAMs are currently being loaded
  public private(set) var isLoadingNOTAMs = false

  /// Whether we have attempted to fetch NOTAMs for the current airport
  public private(set) var hasAttemptedNOTAMFetch = false

  /// What the downloaded NOTAMs propose for the selected runway, once they've been read.
  public private(set) var notamProposal: NOTAMProposal?

  /// Whether the downloaded NOTAMs are being read for proposals.
  public private(set) var isReadingNOTAMs = false

  // MARK: - Computed Properties

  internal var configuration: Configuration {
    .init(weight: weight, flapSetting: flapSetting)
  }

  // MARK: - Abstract Properties (must be overridden)

  /// The Defaults key for the airport
  open var airportDefaultsKey: Defaults.Key<String?> {
    fatalError("Subclasses must override airportDefaultsKey")
  }

  /// The Defaults key for the runway
  open var runwayDefaultsKey: Defaults.Key<String?> {
    fatalError("Subclasses must override runwayDefaultsKey")
  }

  /// The Defaults key for the fuel amount
  open var fuelDefaultsKey: Defaults.Key<Measurement<UnitVolume>> {
    fatalError("Subclasses must override fuelDefaultsKey")
  }

  // MARK: - Initialization

  public init(
    container: ModelContainer,
    calculationService: any PerformanceCalculationService = DefaultPerformanceCalculationService
      .shared,
    notamLoader: (any NOTAMLoaderProtocol)? = nil,
    notamProposer: NOTAMProposer? = nil,
    defaultFlapSetting: FlapSetting
  ) {
    self.container = container
    self.calculationService = calculationService
    self.notamLoader = notamLoader ?? NOTAMLoader.shared
    self.notamProposer = notamProposer ?? NOTAMProposer { nil }

    // temporary values, overwritten by recalculate()
    model = nil
    flapSetting = defaultFlapSetting
    weight = .init(value: 3550, unit: .pounds)
    runway = nil
    conditions = .init()

    model = initializeModel()
    Task { recalculate() }

    setupObservation()
  }

  // MARK: - NOTAM Identifiers

  /// Every identifier the NOTAM service may file an airport's NOTAMs under.
  ///
  /// The service keeps FAA-format NOTAMs — obstacles, procedures — under the FAA identifier (`DEN`)
  /// and ICAO-format ones — runway closures, declared distances, condition reports — under the ICAO
  /// identifier (`KDEN`), with none in common, so an airport's NOTAMs are the two sets together.
  private static func NOTAMIdentifiers(of airport: Airport) -> [String] {
    [airport.locationID, airport.ICAO_ID].compactMap(\.self).reduce(into: []) { identifiers, id in
      if !identifiers.contains(id) { identifiers.append(id) }
    }
  }

  /// Downloads the NOTAMs filed under each of `identifiers` at once and combines them.
  ///
  /// - Throws: Only when every download fails; one that succeeds is enough to show.
  static func downloadNOTAMs(
    for identifiers: [String],
    from startDate: Date?,
    to endDate: Date?,
    using loader: any NOTAMLoaderProtocol
  ) async throws -> [NOTAMResponse] {
    let results = await withTaskGroup(of: Result<[NOTAMResponse], any Error>.self) { group in
      for identifier in identifiers {
        group.addTask {
          do {
            return .success(
              try await loader.fetchNOTAMs(for: identifier, startDate: startDate, endDate: endDate)
            )
          } catch {
            return .failure(error)
          }
        }
      }
      var results: [Result<[NOTAMResponse], any Error>] = []
      for await result in group { results.append(result) }
      return results
    }
    let downloaded = results.compactMap { try? $0.get() }
    if downloaded.isEmpty, let failure = results.first { _ = try failure.get() }
    var seen = Set<Int>()
    return downloaded.flatMap(\.self).filter { seen.insert($0.id).inserted }
  }

  // MARK: - Observation Setup

  private func setupObservation() {
    let airportKey = airportDefaultsKey
    let runwayKey = runwayDefaultsKey
    addTask(
      Task { [weak self] in
        for await (airportID, runwayID) in Defaults.updates(airportKey, runwayKey) {
          if Task.isCancelled { break }
          guard let self else { return }
          do {
            let ids = try await fetchSelectionIDs(airportID: airportID, runwayID: runwayID)
            applyObservedSelection(ids, airportKey: airportKey, runwayKey: runwayKey)
          } catch {
            recordObservationError(error)
          }
        }
      }
    )

    // Observe weight changes
    let fuelKey = fuelDefaultsKey
    addTask(
      Task { [weak self] in
        for await (emptyWeight, fuelDensity, payload, fuel) in Defaults.updates(
          .emptyWeight,
          .fuelDensity,
          .payload,
          fuelKey
        ) {
          if Task.isCancelled { break }
          guard let self else { return }
          weight = emptyWeight + payload + fuel * fuelDensity
        }
      }
    )

    // Observe aircraft type and model type changes
    addTask(
      Task { [weak self] in
        for await _ in Defaults.updates(
          .aircraftTypeSetting,
          .updatedThrustSchedule,
          .useRegressionModel
        ) {
          if Task.isCancelled { break }
          guard let self else { return }
          model = initializeModel()
          recalculate()
        }
      }
    )

    // Observe safety factor changes
    addTask(
      Task { [weak self] in
        for await _ in Defaults.updates(.safetyFactorDry, .safetyFactorWet, .VREFAdditive) {
          if Task.isCancelled { break }
          guard let self else { return }
          recalculate()
        }
      }
    )
  }

  private func addTask(_ task: Task<Void, Never>) {
    cancellables.insert(task)
  }

  /// Resolves the selected airport and runway on a background context, returning
  /// only their `Sendable` persistent identifiers; the models are re-resolved
  /// against the main context in ``applyObservedSelection(_:airportKey:runwayKey:)``.
  @concurrent
  private func fetchSelectionIDs(
    airportID: String?,
    runwayID: String?
  ) async throws -> (airport: PersistentIdentifier?, runway: PersistentIdentifier?) {
    let context = ModelContext(container)
    let (fetchedAirport, fetchedRunway) = try findAirportAndRunway(
      airportID: airportID,
      runwayID: runwayID,
      in: context
    )
    return (fetchedAirport?.persistentModelID, fetchedRunway?.persistentModelID)
  }

  private func applyObservedSelection(
    _ ids: (airport: PersistentIdentifier?, runway: PersistentIdentifier?),
    airportKey: Defaults.Key<String?>,
    runwayKey: Defaults.Key<String?>
  ) {
    let mainContext = container.mainContext
    let airport = ids.airport.flatMap { mainContext.model(for: $0) as? Airport }
    let runway = ids.runway.flatMap { mainContext.model(for: $0) as? Runway }
    if airport == nil { Defaults[airportKey] = nil }
    if runway == nil { Defaults[runwayKey] = nil }
    self.airport = airport
    self.runway = runway
  }

  private func recordObservationError(_ error: any Error) {
    SentrySDK.capture(error: error) { scope in
      scope.setFingerprint(["swiftData", "fetch"])
    }
    self.error = error
  }

  // MARK: - NOTAM Observation

  /// Recomputes performance whenever the selected runway's NOTAM changes.
  ///
  /// Spawns a dedicated task that iterates an `Observations` async sequence whose
  /// emit closure reads the selected runway's NOTAM. Each time any tracked NOTAM
  /// property changes, the sequence emits the new snapshot and performance is
  /// recomputed on the main actor — the same dependency set the NOTAM editing
  /// views observe. The first emission is the current value and is skipped,
  /// because the recompute for the initial selection is already driven by
  /// ``runway``'s `didSet`.
  ///
  /// The loop re-acquires `self` weakly on each element, so it holds no strong
  /// reference across the sequence's suspension points and the view model stays
  /// deallocatable; deallocation cancels the task through `deinit`, and the loop
  /// breaks out on cancellation rather than draining the remaining elements.
  private func setupRunwayNOTAMObservation() {
    notamObservationTask?.cancel()
    guard runway != nil else {
      notamObservationTask = nil
      return
    }
    notamObservationTask = Task { [weak self] in
      let changes = Observations { [weak self] () -> NOTAMInput? in
        guard let self else { return nil }
        return notam.map { NOTAMInput(from: $0) }
      }
      var isFirstEmission = true
      for await _ in changes {
        if Task.isCancelled { break }
        guard let self else { return }
        guard !isFirstEmission else {
          isFirstEmission = false
          continue
        }
        model = initializeModel()
        recalculate()
      }
    }
  }

  // MARK: - NOTAM Fetching

  /// Fetches NOTAMs for the current airport from the API
  /// - Parameter plannedTime: The planned time for the flight, used to filter relevant NOTAMs
  public func fetchNOTAMs(plannedTime: Date = Date()) async {
    guard let airport else {
      downloadedNOTAMs = []
      return
    }

    let primaryIdentifier = airport.locationID

    // Check cache first
    if let cached = await NOTAMCache.shared.get(for: primaryIdentifier) {
      downloadedNOTAMs = filterNOTAMs(cached, relativeTo: plannedTime)
      hasAttemptedNOTAMFetch = true
      readNOTAMs(plannedTime: plannedTime)
      return
    }

    // Fetch from API
    isLoadingNOTAMs = true

    do {
      // Fetch NOTAMs from 7 days before planned time to 30 days after
      let startDate = Calendar.current.date(byAdding: .day, value: -7, to: plannedTime)
      let endDate = Calendar.current.date(byAdding: .day, value: 30, to: plannedTime)

      let notams = try await Self.downloadNOTAMs(
        for: Self.NOTAMIdentifiers(of: airport),
        from: startDate,
        to: endDate,
        using: notamLoader
      )

      // Invalidate old cache only after successfully downloading new NOTAMs
      await NOTAMCache.shared.invalidate(for: primaryIdentifier)

      // Cache the new results
      await NOTAMCache.shared.set(notams, for: primaryIdentifier)

      // Filter for relevant NOTAMs
      downloadedNOTAMs = filterNOTAMs(notams, relativeTo: plannedTime)

      // Mark that we've attempted to fetch NOTAMs
      hasAttemptedNOTAMFetch = true
      readNOTAMs(plannedTime: plannedTime)
    } catch {
      // Log error but don't show to user - NOTAMs are supplementary
      Self.logger.error("Failed to fetch NOTAMs: \(error)")
      downloadedNOTAMs = []
      hasAttemptedNOTAMFetch = true
    }

    isLoadingNOTAMs = false
  }

  /// Reads the downloaded NOTAMs for what they propose for the selected runway, replacing any
  /// reading already under way.
  ///
  /// NOTAMs that have expired by the planned time are skipped: the model takes up to seconds for
  /// each, and nothing they say applies to the flight.
  private func readNOTAMs(plannedTime: Date) {
    notamReadingTask?.cancel()
    guard let runway else {
      notamProposal = nil
      return
    }
    let
      notams = downloadedNOTAMs.filter {
        !$0.hasExpired(before: plannedTime, windowInterval: Self.expiryWindowSeconds)
      },
      proposalRunway = ProposalRunway(runway),
      proposer = notamProposer
    isReadingNOTAMs = true
    notamReadingTask = Task { [weak self] in
      let proposals = await proposer.proposals(for: notams, runways: [proposalRunway])
      guard !Task.isCancelled, let self else { return }
      notamProposal = proposals.byRunway[proposalRunway.name]
      isReadingNOTAMs = false
    }
  }

  /// Filters NOTAMs to show only currently active or upcoming ones
  private func filterNOTAMs(_ notams: [NOTAMResponse], relativeTo date: Date) -> [NOTAMResponse] {
    notams.filter { notam in
      // Include if no end time (permanent) or end time is in the future
      guard let endTime = notam.effectiveEnd else { return true }
      return endTime > date
    }
    .sorted { lhs, rhs in
      // Sort by effective start, earliest first
      lhs.effectiveStart < rhs.effectiveStart
    }
  }

  // MARK: - Model Initialization

  internal func initializeModel() -> (any PerformanceModel)? {
    guard let runway, let airport else { return nil }

    let runwaySnapshot = RunwayInput(from: runway, airport: airport, notam: notam),
      notamInput = notam.map { NOTAMInput(from: $0) },
      aircraftType = Defaults.Keys.aircraftType

    return if Defaults[.useRegressionModel] {
      RegressionPerformanceModel(
        conditions: conditions,
        configuration: configuration,
        runway: runwaySnapshot,
        notam: notamInput,
        aircraftType: aircraftType
      )
    } else {
      TabularPerformanceModel(
        conditions: conditions,
        configuration: configuration,
        runway: runwaySnapshot,
        notam: notamInput,
        aircraftType: aircraftType
      )
    }
  }

  // MARK: - Input-Validation Notes

  /// Generates notes for input-validation issues common to both takeoff and landing.
  ///
  /// Checks wind exceedances (crosswind, tailwind), weight/fuel limits, contamination,
  /// and VREF additive applicability. Subclass view models call this, then append their
  /// own result-dependent notes.
  public func generateInputNotes(
    for operation: Operation,
    VREFAdditiveKts: Double = 0
  ) -> [PerformanceNote] {
    var notes: [PerformanceNote] = []
    let limits = Defaults.Keys.aircraftType.limitations

    // Wind exceedances
    // An unreported wind comes back calm from both components, which exceeds no limit.
    if let runway {
      let crosswindLimit: Measurement<UnitSpeed> =
        flapSetting == .flaps100
        ? limits.maxCrosswind_flaps100 : limits.maxCrosswind_flaps50

      let crosswind = runway.crosswind(conditions: conditions).magnitude
      if crosswind > crosswindLimit {
        notes.append(.crosswindExceedance(crosswind: crosswind, limit: crosswindLimit))
      }

      let headwind = runway.headwind(conditions: conditions)
      if headwind < .zero {
        let tailwind = headwind.magnitude
        if tailwind > limits.maxTailwind {
          notes.append(
            .tailwindExceedance(tailwind: tailwind, limit: limits.maxTailwind)
          )
        }
      }
    }

    // Weight exceedances
    let maxWeight =
      operation == .takeoff
      ? limits.maxTakeoffWeight : limits.maxLandingWeight
    if weight > maxWeight {
      notes.append(.weightAboveMax(weight: weight, limit: maxWeight))
    }
    let zeroFuelWeight = Defaults[.emptyWeight] + Defaults[.payload]
    if zeroFuelWeight > limits.maxZeroFuelWeight {
      notes.append(
        .zeroFuelWeightExceeded(weight: zeroFuelWeight, limit: limits.maxZeroFuelWeight)
      )
    }
    let fuel = Defaults[fuelDefaultsKey]
    if fuel > limits.maxFuel {
      notes.append(.fuelExceedsCapacity(fuel: fuel, limit: limits.maxFuel))
    }

    // Contamination notes (landing only)
    if operation == .landing, let contamination = notam?.contamination {
      if case .rwyCC = contamination {
        if Defaults[.safetyFactorDry] != 1.0 || Defaults[.safetyFactorWet] != 1.0 {
          notes.append(.rwyCCSafetyFactorNotApplied)
        }
      }
      notes.append(.contaminationSupplemental)
    }

    // VREF additive note
    if VREFAdditiveKts > 0 {
      notes.append(.VREFAdditiveApproximate)
    }

    return notes
  }

  // MARK: - Abstract Methods (must be overridden)

  /// Recalculates performance values. Must be overridden by subclasses.
  open func recalculate() {  // swiftlint:disable:this unavailable_function
    fatalError("Subclasses must override recalculate()")
  }

  // MARK: - Deinitialization

  isolated deinit {
    notamObservationTask?.cancel()
    notamReadingTask?.cancel()
    for task in cancellables { task.cancel() }
  }
}
