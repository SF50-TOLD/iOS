import AppIntents
import SF50_Shared
import WidgetKit

/// The widget's configuration: which airport, which leg, and — for a landing — which flap setting.
///
/// Every parameter's default reproduces the behavior the widget had before it was configurable. A
/// widget already on someone's home screen is handed a default-initialized instance of this intent, so
/// a default that named a specific airport, or chose the landing leg, would silently change or blank
/// every pinned widget on upgrade.
struct SelectedAirportConfigurationIntent: WidgetConfigurationIntent {
  static let title: LocalizedStringResource = "Select Airport"

  static let description = IntentDescription(
    "Choose which airport this widget shows, and whether it shows takeoff or landing numbers."
  )

  static var parameterSummary: some ParameterSummary {
    When(\.$operation, .equalTo, SF50_Shared.Operation.landing) {
      Summary("Show \(\.$operation) numbers for \(\.$airport)") {
        \.$flapSetting
      }
    } otherwise: {
      Summary("Show \(\.$operation) numbers for \(\.$airport)")
    }
  }

  /// The airport to show, or `nil` to follow whichever airport the app has selected.
  @Parameter(
    title: "Airport",
    description: "Leave empty to follow the airport selected in the app."
  )
  var airport: AirportEntity?

  /// Which leg to calculate.
  @Parameter(title: "Phase", default: .takeoff)
  var operation: SF50_Shared.Operation

  /// The landing flap configuration. The AFM publishes takeoff performance at flaps 50% only.
  @Parameter(title: "Landing Flaps", default: .flaps100)
  var flapSetting: FlapSetting
}
