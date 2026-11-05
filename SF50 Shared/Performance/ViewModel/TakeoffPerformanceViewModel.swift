public import Defaults
public import Foundation
public import MeasurementKit
public import Observation
import Sentry
public import SwiftData

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
/// When a NOTAM specifies an obstacle off the departure end, ``climbRequirement`` gives what
/// clearing it takes: the gradient from the end of the takeoff distance, where the aircraft crosses
/// the 50 ft screen, to the obstacle's height.
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

  /// What clearing the NOTAMed obstacle requires of the takeoff climb, or `nil` where there is no
  /// obstacle or no takeoff distance to measure from.
  public var climbRequirement: ClimbRequirement? {
    guard let takeoffDistance = takeoffDistance.nominalOrClamped,
      let availableTakeoffRun,
      let obstacle = notam.flatMap({ NOTAMInput(from: $0).obstacle })
    else { return nil }

    return obstacle.climbRequirement(
      takeoffDistance: takeoffDistance,
      availableTakeoffRun: availableTakeoffRun
    )
  }

  /// The climb gradient needed to clear the NOTAMed obstacle, or `nil` where clearing it needs no
  /// particular gradient or no gradient can.
  public var requiredClimbGradient: Measurement<UnitSlope>? {
    guard case .gradient(let required) = climbRequirement else { return nil }
    return required
  }

  public var offscaleLow: Bool {
    let valuesOffscaleLow =
      takeoffRun.isOffscaleLow || takeoffDistance.isOffscaleLow
      || takeoffClimbRate.isOffscaleLow || takeoffClimbGradient.isOffscaleLow
    return valuesOffscaleLow || (model?.takeoffInputsOffscaleLow ?? false)
  }

  public var offscaleHigh: Bool {
    let valuesOffscaleHigh =
      takeoffRun.isOffscaleHigh || takeoffDistance.isOffscaleHigh
      || takeoffClimbRate.isOffscaleHigh || takeoffClimbGradient.isOffscaleHigh
    return valuesOffscaleHigh || (model?.takeoffInputsOffscaleHigh ?? false)
  }

  public var availableTakeoffRun: Measurement<UnitLength>? {
    runway?.availableTakeoffRun(notamedBy: notam)
  }
  public var availableTakeoffDistance: Measurement<UnitLength>? {
    runway?.availableTakeoffDistance(notamedBy: notam)
  }

  // MARK: Overrides

  override public var airportDefaultsKey: Defaults.Key<String?> { .takeoffAirport }
  override public var runwayDefaultsKey: Defaults.Key<String?> { .takeoffRunway }
  override public var fuelDefaultsKey: Defaults.Key<Measurement<UnitVolume>> { .takeoffFuel }

  // MARK: Initializers

  public init(
    container: ModelContainer,
    calculationService: any PerformanceCalculationService = DefaultPerformanceCalculationService
      .shared,
    notamLoader: (any NOTAMLoaderProtocol)? = nil
  ) {
    takeoffRun = .notAvailable
    takeoffDistance = .notAvailable
    takeoffClimbGradient = .notAvailable
    takeoffClimbRate = .notAvailable

    super.init(
      container: container,
      calculationService: calculationService,
      notamLoader: notamLoader,
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
      notes = noteInputs.map { PerformanceNotes.takeoffNotes(for: report, inputs: $0) } ?? []
    } catch {
      SentrySDK.logger.error(
        "Unexpected takeoff calculation error: \(error.localizedDescription)",
        attributes: ["airport": airport?.locationID ?? "unknown"]
      )
      takeoffRun = .invalid
      takeoffDistance = .invalid
      takeoffClimbGradient = .invalid
      takeoffClimbRate = .invalid
      takeoffReport = nil
      notes = []
    }
  }
}
