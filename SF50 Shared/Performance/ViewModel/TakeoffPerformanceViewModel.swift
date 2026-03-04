import Defaults
import Foundation
import Observation
import SwiftData

/// View model for takeoff performance calculations.
///
/// ``TakeoffPerformanceViewModel`` provides reactive takeoff performance values
/// that update automatically when inputs change. It observes user settings for
/// airport, runway, weight, and conditions, then calculates:
///
/// - ``takeoffRun`` - Ground run distance
/// - ``takeoffDistance`` - Total distance over 50ft obstacle
/// - ``takeoffClimbGradient`` - Initial climb gradient
/// - ``takeoffClimbRate`` - Initial climb rate
///
/// ## Required Climb Gradient
///
/// When a NOTAM specifies obstacles off the departure end, the view model
/// calculates ``requiredClimbGradient`` to clear the obstacle based on:
/// - Distance from runway end to obstacle
/// - Obstacle height above runway
/// - Computed liftoff point (takeoff run)
///
/// ## NOTAM Display
///
/// Both configured NOTAMs (user-entered runway restrictions) and downloaded
/// NOTAMs (from FAA API) are tracked via ``configuredNOTAMCount`` and
/// ``downloadedNOTAMCount``.
@Observable
@MainActor
public final class TakeoffPerformanceViewModel: BasePerformanceViewModel {
  // MARK: Outputs

  public private(set) var takeoffRun: Value<Measurement<UnitLength>>
  public private(set) var takeoffDistance: Value<Measurement<UnitLength>>
  public private(set) var takeoffClimbGradient: Value<Measurement<UnitSlope>>
  public private(set) var takeoffClimbRate: Value<Measurement<UnitSpeed>>
  public private(set) var takeoffReport: TakeoffReport?
  public private(set) var notes: [PerformanceNote] = []

  // MARK: Computed Properties

  public var NOTAMCount: Int {
    guard let notam, !notam.isEmpty else { return 0 }
    var count = 0
    if notam.contamination != nil { count += 1 }
    if notam.takeoffDistanceShortening.value > 0 { count += 1 }
    if notam.obstacleHeight.value > 0 || notam.obstacleDistance.value > 0 { count += 1 }
    return count
  }

  /// Number of configured (user-entered) NOTAMs affecting this runway
  public var configuredNOTAMCount: Int { NOTAMCount }

  /// Number of downloaded NOTAMs from the API
  public var downloadedNOTAMCount: Int { downloadedNOTAMs.count }

  public var requiredClimbGradient: Measurement<UnitSlope>? {
    guard case .value(let takeoffRun) = takeoffRun,
      let availableTakeoffRun,
      let obstacleHeight = runway?.notam?.obstacleHeight,
      let obstacleDistance = runway?.notam?.obstacleDistance,
      obstacleHeight.value > 0
    else { return nil }

    let distanceFromRunwayStart = obstacleDistance + availableTakeoffRun
    let distanceFromLiftoffPoint = distanceFromRunwayStart - takeoffRun

    let slope = (obstacleHeight / distanceFromLiftoffPoint)
    return .init(value: slope, unit: .gradient)
  }

  public var offscaleLow: Bool {
    let valuesOffscaleLow =
      takeoffRun == .offscaleLow || takeoffDistance == .offscaleLow
      || takeoffClimbRate == .offscaleLow || takeoffClimbGradient == .offscaleLow
    return valuesOffscaleLow || (model?.takeoffInputsOffscaleLow ?? false)
  }

  public var offscaleHigh: Bool {
    let valuesOffscaleHigh =
      takeoffRun == .offscaleHigh || takeoffDistance == .offscaleHigh
      || takeoffClimbRate == .offscaleHigh || takeoffClimbGradient == .offscaleHigh
    return valuesOffscaleHigh || (model?.takeoffInputsOffscaleHigh ?? false)
  }

  public var availableTakeoffRun: Measurement<UnitLength>? { runway?.notamedTakeoffRun }
  public var availableTakeoffDistance: Measurement<UnitLength>? { runway?.notamedTakeoffDistance }

  // MARK: Overrides

  override public var airportDefaultsKey: Defaults.Key<String?> { .takeoffAirport }
  override public var runwayDefaultsKey: Defaults.Key<String?> { .takeoffRunway }
  override public var fuelDefaultsKey: Defaults.Key<Measurement<UnitVolume>> { .takeoffFuel }
  override public var defaultFlapSetting: FlapSetting { .flaps50 }

  // MARK: Initializers

  public init(
    container: ModelContainer,
    calculationService: PerformanceCalculationService = DefaultPerformanceCalculationService.shared
  ) {
    takeoffRun = .notAvailable
    takeoffDistance = .notAvailable
    takeoffClimbGradient = .notAvailable
    takeoffClimbRate = .notAvailable

    super.init(
      container: container,
      calculationService: calculationService,
      defaultFlapSetting: .flaps50
    )
  }

  // MARK: Calculation

  override public func recalculate() {
    guard let model else {
      takeoffRun = .notAvailable
      takeoffDistance = .notAvailable
      takeoffClimbGradient = .notAvailable
      takeoffClimbRate = .notAvailable
      takeoffReport = nil
      notes = []
      return
    }

    do {
      let safetyFactor = Defaults[.safetyFactorDry]
      let report = try calculationService.calculateTakeoff(
        for: model,
        safetyFactor: safetyFactor
      )
      takeoffReport = report
      takeoffRun = report.results.takeoffRun
      takeoffDistance = report.results.takeoffDistance
      takeoffClimbGradient = report.results.takeoffClimbGradient
      takeoffClimbRate = report.results.takeoffClimbRate
      notes = generateNotes()
    } catch {
      takeoffRun = .invalid
      takeoffDistance = .invalid
      takeoffClimbGradient = .invalid
      takeoffClimbRate = .invalid
      takeoffReport = nil
      notes = []
    }
  }

  // MARK: Notes

  private func generateNotes() -> [PerformanceNote] {
    var notes: [PerformanceNote] = []

    // Offscale warnings
    if offscaleHigh { notes.append(.offscaleHigh) }
    if offscaleLow { notes.append(.offscaleLow) }

    // Input-validation notes
    notes += generateInputNotes(for: .takeoff)

    // Distance exceedances
    if let available = availableTakeoffRun,
      let run = takeoffRun.nominal, run > available
    {
      notes.append(.takeoffRunExceedsAvailable(required: run, available: available))
    }
    if let available = availableTakeoffDistance,
      let dist = takeoffDistance.nominal, dist > available
    {
      notes.append(.takeoffDistanceExceedsAvailable(required: dist, available: available))
    }

    // Climb gradient
    if let required = requiredClimbGradient {
      notes.append(
        .insufficientClimbGradient(
          required: required,
          actual: takeoffClimbGradient
        )
      )
    }

    return notes
  }
}
