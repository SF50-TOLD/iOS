import Defaults
public import SwiftData

import Algorithms

/// Keeps the airport identifiers the app stores pointing at the right airports when a new
/// dataset is installed.
///
/// A dataset can key an airport differently from the one before it (see ``AirportAlias``). The
/// favorites, recents, and selected airports are stored by key, so after an install each one the
/// new dataset doesn't use is replaced by the key of the airport it now names.
public enum StoredAirportIdentifiers {

  /// Replaces every stored airport identifier the dataset in `context` no longer uses with its
  /// current key, and forgets a selected runway the remapped airport no longer has.
  public static func remap(in context: ModelContext) throws {
    Defaults[.favoriteAirports] = Set(
      try Defaults[.favoriteAirports].map { try currentID(for: $0, in: context) }
    )
    Defaults[.recentAirports] = Array(
      try Defaults[.recentAirports].map { try currentID(for: $0, in: context) }.uniqued()
    )
    try remapSelection(airport: .takeoffAirport, runway: .takeoffRunway, in: context)
    try remapSelection(airport: .landingAirport, runway: .landingRunway, in: context)
  }

  private static func currentID(for airportID: String, in context: ModelContext) throws -> String {
    try findAirport(for: airportID, in: context)?.recordID ?? airportID
  }

  private static func remapSelection(
    airport airportKey: Defaults.Key<String?>,
    runway runwayKey: Defaults.Key<String?>,
    in context: ModelContext
  ) throws {
    guard let storedID = Defaults[airportKey],
      let airport = try findAirport(for: storedID, in: context),
      airport.recordID != storedID
    else { return }

    Defaults[airportKey] = airport.recordID
    if let runwayName = Defaults[runwayKey],
      !airport.runways.contains(where: { $0.name == runwayName })
    {
      Defaults[runwayKey] = nil
    }
  }
}
