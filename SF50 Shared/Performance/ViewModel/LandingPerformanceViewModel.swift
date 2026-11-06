public import Defaults
public import Foundation
public import Observation
import Sentry
public import SwiftData

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

  /// Landing distance available on the selected runway, less any NOTAMed shortening, or `nil`
  /// until a runway is selected.
  ///
  /// A landing declares one distance rather than a separate run and distance, so both the ground
  /// run and the total landing distance are measured against this length.
  public var availableLandingDistance: Measurement<UnitLength>? {
    runway?.availableLandingDistance(notamedBy: notam)
  }

  // MARK: Overrides

  override public var airportDefaultsKey: Defaults.Key<String?> { .landingAirport }
  override public var runwayDefaultsKey: Defaults.Key<String?> { .landingRunway }
  override public var fuelDefaultsKey: Defaults.Key<Measurement<UnitVolume>> { .landingFuel }

  // MARK: Initializers

  public init(
    container: ModelContainer,
    calculationService: any PerformanceCalculationService = DefaultPerformanceCalculationService
      .shared,
    notamLoader: (any NOTAMLoaderProtocol)? = nil
  ) {
    Vref = .notAvailable
    landingRun = .notAvailable
    landingDistance = .notAvailable
    meetsGoAroundClimbGradient = .notAvailable

    super.init(
      container: container,
      calculationService: calculationService,
      notamLoader: notamLoader,
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
      let settings = Defaults.Keys.performanceSettings
      let report = try calculationService.calculateLanding(
        for: model,
        safetyFactor: settings.landingSafetyFactor(for: notam?.contamination),
        VREFAdditiveKts: settings.VREFAdditiveKts
      )
      landingReport = report
      Vref = report.results.Vref
      landingRun = report.results.landingRun
      landingDistance = report.results.landingDistance
      meetsGoAroundClimbGradient = report.results.meetsGoAroundClimbGradient
      notes = noteInputs.map { PerformanceNotes.landingNotes(for: report, inputs: $0) } ?? []
    } catch {
      SentrySDK.logger.error(
        "Unexpected landing calculation error: \(error.localizedDescription)",
        attributes: ["airport": airport?.locationID ?? "unknown"]
      )
      Vref = .invalid
      landingRun = .invalid
      landingDistance = .invalid
      meetsGoAroundClimbGradient = .invalid
      landingReport = nil
      notes = []
    }
  }
}
