import AppIntents
import Defaults
import Foundation
import MeasurementKit
import SF50_Shared

/// Reports takeoff or landing numbers for one runway.
///
/// The intent never returns a bare number. It comes back with a snippet showing the distance beside
/// the distance available, the wind decomposed onto the runway, and the weather the answer came from —
/// and when the AFM cannot answer for the conditions, it refuses in words rather than rounding into a
/// number nobody can trace.
struct RunwayNumbersIntent: AppIntent {
  static let title: LocalizedStringResource = "Get Runway Numbers"

  static let description = IntentDescription(
    "Calculates takeoff or landing distances for a runway using current weather and the weight entered in the app.",
    categoryName: "Performance"
  )

  static let supportedModes: IntentModes = .background

  static var parameterSummary: some ParameterSummary {
    When(\.$operation, .equalTo, SF50_Shared.Operation.landing) {
      Summary("Get \(\.$operation) numbers for \(\.$runway) at \(\.$airport)") {
        \.$flapSetting
      }
    } otherwise: {
      Summary("Get \(\.$operation) numbers for \(\.$runway) at \(\.$airport)")
    }
  }

  /// The airport, or `nil` to use whichever airport the app has selected for this leg.
  @Parameter(
    title: "Airport",
    description: "Leave empty to use the airport selected in the app."
  )
  var airport: AirportEntity?

  /// The runway, or `nil` to use whichever runway the app has selected for this leg.
  @Parameter(
    title: "Runway",
    description: "Leave empty to use the runway selected in the app."
  )
  var runway: RunwayEntity?

  /// Which leg to calculate.
  @Parameter(title: "Phase", default: .takeoff)
  var operation: SF50_Shared.Operation

  /// The landing flap configuration. The AFM publishes takeoff performance at flaps 50% only.
  @Parameter(title: "Landing Flaps", default: .flaps100)
  var flapSetting: FlapSetting

  func perform() async throws
    -> some ReturnsValue<RunwayEntity> & ShowsSnippetIntent & ProvidesDialog
  {
    // A saved shortcut names its own airport inside the runway it stored. Preferring that over the
    // app's current selection is what stops the intent quietly answering for a different field's
    // runway 30.
    let performance = try await RunwayPerformanceService()
      .performance(
        airportRecordID: airport?.id ?? runway?.airportRecordID,
        operation: operation,
        flapSetting: flapSetting
      )

    guard let name = runway?.name ?? operation.selectedRunwayName else {
      throw PerformanceLookupError.noRunwaySelected
    }
    guard runway.map({ $0.airportRecordID == performance.airportRecordID }) ?? true,
      let snapshot = performance.runway(named: name)
    else {
      throw PerformanceLookupError.runwayNotFound(
        name: name,
        airport: performance.airportDisplayID
      )
    }
    guard let conditions = performance.conditions else {
      throw PerformanceLookupError.weatherUnavailable(airport: performance.airportDisplayID)
    }

    let result = performance.results[name]
    return .result(
      value: entity(for: snapshot, in: performance, result: result, conditions: conditions),
      dialog: .init(stringLiteral: dialog(for: snapshot, result: result)),
      snippetIntent: RunwayNumbersSnippetIntent(
        airportRecordID: performance.airportRecordID,
        runwayName: name,
        operation: operation,
        flapSetting: flapSetting
      )
    )
  }
}

// MARK: - Scoping the runway picker

extension RunwayNumbersIntent {
  /// The airport ``RunwayEntityQuery`` should offer runways from, resolved as ``perform()`` resolves
  /// it: the airport this intent names, or the one the app has selected for this leg.
  ///
  /// It is never optional, and that is the whole point. The query reads this through an
  /// `IntentProjection`, whose subscript hands back a parameter's *unwrapped* type — so projecting
  /// ``airport`` itself would unwrap precisely the empty value that parameter's own description
  /// invites, and the fallback written beside it could never run. An empty string means no airport is
  /// named here or selected in the app.
  var scopedAirportRecordID: String {
    airport?.id ?? operation.selectedAirportRecordID ?? ""
  }
}

// MARK: - Building the answer

extension RunwayNumbersIntent {
  private var operationName: String {
    switch operation {
      case .takeoff: String(localized: "takeoff")
      case .landing: String(localized: "landing")
    }
  }

  /// The wording a refusal keeps when it is spoken rather than drawn.
  ///
  /// Collapsing every one of these into "no distance is published" would tell a pilot the same thing
  /// whether the AFM simply lacks data or the aircraft is off the top of the chart — which are not the
  /// same news.
  private static func refusal(
    for distance: Value<Measurement<UnitLength>>?,
    operation: String
  ) -> String {
    switch distance {
      case .offscaleHigh:
        String(localized: "the required \(operation) distance is beyond the published data.")
      case .offscaleLow:
        String(localized: "conditions are below the published data.")
      case .notAuthorized:
        String(localized: "this configuration isn’t authorized.")
      case .invalid:
        String(localized: "the \(operation) calculation failed.")
      default:
        String(localized: "no \(operation) distance is published for these conditions.")
    }
  }

  /// A short machine-readable echo of ``refusal(for:operation:)`` for shortcuts that chain on it.
  private static func status(of distance: Value<Measurement<UnitLength>>) -> String? {
    switch distance {
      case .value, .valueWithUncertainty: nil
      case .offscaleHigh: String(localized: "Offscale high")
      case .offscaleLow: String(localized: "Offscale low")
      case .notAuthorized: String(localized: "Not authorized")
      case .invalid: String(localized: "Invalid")
      case .notAvailable: String(localized: "Not available")
    }
  }

  private func entity(
    for snapshot: RunwaySnapshot,
    in performance: AirportPerformance,
    result: RunwayPerformance?,
    conditions: Conditions
  ) -> RunwayEntity {
    let entity = RunwayEntity(
      airportRecordID: performance.airportRecordID,
      airportDisplayID: performance.airportDisplayID,
      name: snapshot.name
    )
    entity.groundRun = result?.groundRun.nominal
    entity.distance = result?.distance.nominal
    entity.availableDistance = snapshot.availableDistance(for: operation)
    entity.climbGradientFtNM =
      result?.climbGradient?.nominal?
      .converted(to: .feetPerNauticalMile).value
    entity.VREF = result?.VREF?.nominal
    entity.status = result.flatMap { Self.status(of: $0.distance) }
    entity.headwind = snapshot.headwind(conditions: conditions)
    entity.crosswind = snapshot.crosswind(conditions: conditions)
    return entity
  }

  /// What Siri says aloud. The snippet carries the detail; this is the one sentence a pilot can act on
  /// without looking at the screen.
  private func dialog(for snapshot: RunwaySnapshot, result: RunwayPerformance?) -> String {
    let unit = Defaults[.runwayLengthUnit],
      available = snapshot.availableDistance(for: operation).converted(to: unit)

    guard let required = result?.distance.nominal?.converted(to: unit) else {
      return String(
        localized:
          "Runway \(snapshot.name): \(Self.refusal(for: result?.distance, operation: operationName))"
      )
    }

    return required > available
      ? String(
        localized:
          "Runway \(snapshot.name) needs \(required, format: .length), more than the \(available, format: .length) available."
      )
      : String(
        localized:
          "Runway \(snapshot.name) needs \(required, format: .length) of \(available, format: .length) available."
      )
  }
}
