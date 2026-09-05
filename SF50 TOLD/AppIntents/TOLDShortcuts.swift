import AppIntents

/// The shortcuts the system offers without the pilot building one first.
///
/// Every phrase has to name the app, so these read as the two questions worth asking with hands full:
/// the departure numbers and the arrival numbers.
struct TOLDShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: RunwayNumbersIntent(),
      phrases: [
        "Get runway numbers in \(.applicationName)",
        "Get takeoff numbers in \(.applicationName)",
        "Get landing numbers in \(.applicationName)",
        "What are my numbers in \(.applicationName)"
      ],
      shortTitle: "Runway Numbers",
      systemImageName: "airplane.departure"
    )
  }
}
