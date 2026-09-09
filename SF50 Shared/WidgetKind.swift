/// The kind strings WidgetKit uses to name this app's widgets.
///
/// A widget's kind is the only thing tying the extension's `WidgetConfiguration` to the app's
/// `WidgetCenter.reloadTimelines(ofKind:)` call: WidgetKit matches the two by string, and a reload
/// naming a kind no widget declares is silently dropped. Both sides read the kind from here so that
/// they cannot disagree.
public enum WidgetKind {
  /// The widget showing takeoff or landing performance for every runway at a chosen airport.
  public static let selectedAirportPerformance = "SF50_SelectedAirport"
}
