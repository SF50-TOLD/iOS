import Defaults
import Foundation
import Observation
import SwiftData

/// View model for landing performance calculations.
///
/// ``LandingPerformanceViewModel`` provides reactive landing performance values
/// that update automatically when inputs change. It observes user settings for
/// airport, runway, weight, and conditions, then calculates:
///
/// - ``Vref`` - Reference approach speed
/// - ``landingRun`` - Ground run distance after touchdown
/// - ``landingDistance`` - Total distance over 50ft obstacle
/// - ``meetsGoAroundClimbGradient`` - Whether go-around gradient can be achieved
///
/// ## Go-Around Capability
///
/// The ``meetsGoAroundClimbGradient`` property indicates whether the aircraft
/// can meet the required go-around climb gradient at the current weight and
/// conditions. This is important for approach planning.
///
/// ## NOTAM Display
///
/// Both configured NOTAMs (user-entered runway restrictions) and downloaded
/// NOTAMs (from FAA API) are tracked via ``configuredNOTAMCount`` and
/// ``downloadedNOTAMCount``.
@Observable
@MainActor
public final class LandingPerformanceViewModel: BasePerformanceViewModel {
  // MARK: Outputs

  public private(set) var Vref: Value<Measurement<UnitSpeed>>
  public private(set) var landingRun: Value<Measurement<UnitLength>>
  public private(set) var landingDistance: Value<Measurement<UnitLength>>
  public private(set) var meetsGoAroundClimbGradient: Value<Bool>
  public private(set) var landingReport: LandingReport?
  public private(set) var notes: [PerformanceNote] = []

  // MARK: Computed Properties

  public var NOTAMCount: Int {
    guard let notam, !notam.isEmpty else { return 0 }
    var count = 0
    if notam.contamination != nil { count += 1 }
    if notam.landingDistanceShortening.value > 0 { count += 1 }
    return count
  }

  /// Number of configured (user-entered) NOTAMs affecting this runway
  public var configuredNOTAMCount: Int { NOTAMCount }

  /// Number of downloaded NOTAMs from the API
  public var downloadedNOTAMCount: Int { downloadedNOTAMs.count }

  public var requiredClimbGradient: Measurement<UnitSlope>? {
    guard let availableLandingRun,
      let obstacleHeight = runway?.notam?.obstacleHeight,
      let obstacleDistance = runway?.notam?.obstacleDistance
    else { return nil }

    let distanceFromRunwayStart = obstacleDistance + availableLandingRun

    let slope = (obstacleHeight / distanceFromRunwayStart)
    return .init(value: slope, unit: .gradient)
  }

  public var offscaleLow: Bool {
    let valuesOffscaleLow =
      Vref == .offscaleLow || landingRun == .offscaleLow || landingDistance == .offscaleLow
    return valuesOffscaleLow || (model?.landingInputsOffscaleLow ?? false)
  }

  public var offscaleHigh: Bool {
    let valuesOffscaleHigh =
      Vref == .offscaleHigh || landingRun == .offscaleHigh || landingDistance == .offscaleHigh
    return valuesOffscaleHigh || (model?.landingInputsOffscaleHigh ?? false)
  }

  public var availableLandingRun: Measurement<UnitLength>? { runway?.notamedLandingDistance }

  // MARK: Overrides

  override public var airportDefaultsKey: Defaults.Key<String?> { .landingAirport }
  override public var runwayDefaultsKey: Defaults.Key<String?> { .landingRunway }
  override public var fuelDefaultsKey: Defaults.Key<Measurement<UnitVolume>> { .landingFuel }
  override public var defaultFlapSetting: FlapSetting { .flaps100 }

  // MARK: Initializers

  public init(
    container: ModelContainer,
    calculationService: PerformanceCalculationService = DefaultPerformanceCalculationService.shared
  ) {
    Vref = .notAvailable
    landingRun = .notAvailable
    landingDistance = .notAvailable
    meetsGoAroundClimbGradient = .notAvailable

    super.init(
      container: container,
      calculationService: calculationService,
      defaultFlapSetting: .flaps100
    )
  }

  // MARK: Calculation

  override public func recalculate() {
    guard let model else {
      Vref = .notAvailable
      landingRun = .notAvailable
      landingDistance = .notAvailable
      meetsGoAroundClimbGradient = .notAvailable
      landingReport = nil
      notes = []
      return
    }

    do {
      let safetyFactor: Double =
        switch notam?.contamination {
          case .rwyCC: 1.0  // LDF already includes safety margin per AC 91-79B
          case .some: Defaults[.safetyFactorWet]
          case .none: Defaults[.safetyFactorDry]
        }
      let VREFAdditiveKts = Defaults[.VREFAdditive].converted(to: .knots).value
      let report = try calculationService.calculateLanding(
        for: model,
        safetyFactor: safetyFactor,
        VREFAdditiveKts: VREFAdditiveKts
      )
      landingReport = report
      Vref = report.results.Vref
      landingRun = report.results.landingRun
      landingDistance = report.results.landingDistance
      meetsGoAroundClimbGradient = report.results.meetsGoAroundClimbGradient
      notes = generateNotes(VREFAdditiveKts: VREFAdditiveKts)
    } catch {
      Vref = .invalid
      landingRun = .invalid
      landingDistance = .invalid
      meetsGoAroundClimbGradient = .invalid
      landingReport = nil
      notes = []
    }
  }

  // MARK: Notes

  private func generateNotes(VREFAdditiveKts: Double) -> [PerformanceNote] {
    var notes: [PerformanceNote] = []

    // Offscale warnings
    if offscaleHigh { notes.append(.offscaleHigh) }
    if offscaleLow { notes.append(.offscaleLow) }

    // Input-validation notes
    notes += generateInputNotes(for: .landing, VREFAdditiveKts: VREFAdditiveKts)

    // Distance exceedance
    if let available = availableLandingRun,
      let dist = landingDistance.nominal, dist > available
    {
      notes.append(.landingDistanceExceedsAvailable(required: dist, available: available))
    }

    // Go-around climb gradient
    if case .value(let meets) = meetsGoAroundClimbGradient, !meets {
      notes.append(.doesNotMeetGoAroundGradient)
    }

    return notes
  }
}
