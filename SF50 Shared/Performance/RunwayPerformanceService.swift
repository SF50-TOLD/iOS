import Defaults
import Foundation
import MeasurementKit
import SwiftData

/// Calculates runway performance without a user interface.
///
/// The widget timeline and the App Intents surfaces both need the same four steps — resolve the
/// airport, load the weather, build the configuration, calculate every runway — with different output
/// sinks. This is that pipeline in one place.
///
/// ## Configuration
///
/// Weight comes from the empty weight, payload and fuel settings, using the fuel quantity for the leg
/// being calculated. Safety factor, VREF additive, model choice and aircraft type all come from the
/// same settings the app itself reads, so a number here matches the number on screen.
@MainActor
public final class RunwayPerformanceService {
  private let calculationService = DefaultPerformanceCalculationService.shared
  private let modelContext: ModelContext

  /// Creates a service reading the shared app-group store.
  public init() {
    modelContext = ModelContext(AppGroupStore.container)
  }

  /// Calculates performance for every runway at an airport.
  ///
  /// - Parameters:
  ///   - airportRecordID: The airport to calculate for, or `nil` to follow the app's own selection for
  ///     this leg.
  ///   - operation: The leg being flown.
  ///   - flapSetting: The landing flap configuration. A takeoff is calculated at flaps 50% whatever
  ///     is passed here, which is the only setting the AFM publishes takeoff data for.
  /// - Returns: The airport, its runways, the conditions used, and a result per runway.
  /// - Throws: ``PerformanceLookupError`` when the store, the selection, or the airport is not usable.
  public func performance(
    airportRecordID: String?,
    operation: Operation,
    flapSetting: FlapSetting = .flaps100
  ) async throws -> AirportPerformance {
    guard Defaults[.schemaVersion] == latestSchemaVersion else {
      throw PerformanceLookupError.navigationDataOutOfDate
    }

    let airport = try resolveAirport(recordID: airportRecordID, operation: operation)
    let runways = airport.runways.map(RunwaySnapshot.init(from:))
    let conditions = await loadConditions(for: airport)

    return .init(
      airportRecordID: airport.recordID,
      airportName: airport.name,
      airportDisplayID: airport.displayID,
      operation: operation,
      runways: runways,
      conditions: conditions,
      results: conditions.map {
        results(for: airport, conditions: $0, operation: operation, flapSetting: flapSetting)
      } ?? [:]
    )
  }
}

// MARK: - Resolving the airport

extension RunwayPerformanceService {
  private func resolveAirport(recordID: String?, operation: Operation) throws -> Airport {
    let selected = recordID ?? Defaults[selectionKey(for: operation)]
    guard let selected else { throw PerformanceLookupError.noAirportSelected }
    guard let airport = try findAirport(for: selected, in: modelContext) else {
      throw PerformanceLookupError.airportNotFound
    }
    return airport
  }

  private func selectionKey(for operation: Operation) -> Defaults.Key<String?> {
    switch operation {
      case .takeoff: .takeoffAirport
      case .landing: .landingAirport
    }
  }
}

// MARK: - Weather

extension RunwayPerformanceService {
  /// How long to wait for a first observation before giving up.
  ///
  /// The conditions stream yields `.loading` until weather arrives and never completes on its own, so
  /// waiting on it unbounded is waiting forever. WidgetKit would eventually kill a stuck timeline, but
  /// an App Intent has no such backstop — a spoken request would simply never answer.
  private static let weatherTimeout = Duration.seconds(15)

  private static func firstConditions(for key: WeatherLoader.Key) async -> Conditions? {
    await WeatherLoader.shared.load(force: true)
    for await loadable in await WeatherLoader.shared.streamConditions(for: key) {
      if case .value(let conditions) = loadable { return conditions }
    }
    return nil
  }

  private func loadConditions(for airport: Airport) async -> Conditions? {
    let key = WeatherLoader.Key(airport: airport, time: Date())
    return await withTaskGroup(of: Conditions?.self) { group in
      group.addTask { await Self.firstConditions(for: key) }
      group.addTask {
        try? await Task.sleep(for: Self.weatherTimeout)
        return nil
      }
      var conditions: Conditions?
      if let first = await group.next() { conditions = first }
      group.cancelAll()
      return conditions
    }
  }
}

// MARK: - Calculation

extension RunwayPerformanceService {
  /// Mirrors `LandingPerformanceViewModel`'s choice exactly.
  ///
  /// A reported runway condition code is the case worth spelling out: its landing distance factor
  /// already carries the safety margin under AC 91-79B, so applying the wet factor on top would
  /// report a longer distance than the app does for the same runway.
  private static func landingSafetyFactor(for contamination: Contamination?) -> Double {
    switch contamination {
      case .rwyCC: 1.0
      case .some: Defaults[.safetyFactorWet]
      case .none: Defaults[.safetyFactorDry]
    }
  }

  private func results(
    for airport: Airport,
    conditions: Conditions,
    operation: Operation,
    flapSetting: FlapSetting
  ) -> [String: RunwayPerformance] {
    let
      configuration = Configuration(
        weight: weight(for: operation),
        flapSetting: operation == .takeoff ? .flaps50 : flapSetting
      ),
      useRegressionModel = Defaults[.useRegressionModel],
      aircraftType = Defaults.Keys.aircraftType,
      VREFAdditiveKts = Defaults[.VREFAdditive].converted(to: .knots).value

    return airport.runways.reduce(into: [:]) { results, runway in
      let input = RunwayInput(from: runway, airport: airport)
      let model = calculationService.createPerformanceModel(
        conditions: conditions,
        configuration: configuration,
        runway: input,
        notam: input.notam,
        useRegressionModel: useRegressionModel,
        aircraftType: aircraftType
      )
      results[runway.name] = performance(
        from: model,
        operation: operation,
        contamination: input.notam?.contamination,
        VREFAdditiveKts: VREFAdditiveKts
      )
    }
  }

  private func performance(
    from model: any PerformanceModel,
    operation: Operation,
    contamination: Contamination?,
    VREFAdditiveKts: Double
  ) -> RunwayPerformance {
    do {
      switch operation {
        case .takeoff:
          let report = try calculationService.calculateTakeoff(
            for: model,
            safetyFactor: Defaults[.safetyFactorDry]
          )
          return .init(takeoff: report.results)
        case .landing:
          let report = try calculationService.calculateLanding(
            for: model,
            safetyFactor: Self.landingSafetyFactor(for: contamination),
            VREFAdditiveKts: VREFAdditiveKts
          )
          return .init(landing: report.results)
      }
    } catch {
      return .init(invalidFor: operation)
    }
  }

  private func weight(for operation: Operation) -> Measurement<UnitMass> {
    let fuel =
      switch operation {
        case .takeoff: Defaults[.takeoffFuel]
        case .landing: Defaults[.landingFuel]
      }
    return Defaults[.emptyWeight] + Defaults[.payload] + fuel * Defaults[.fuelDensity]
  }
}
