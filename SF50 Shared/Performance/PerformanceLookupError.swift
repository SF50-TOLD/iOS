import Foundation

/// A performance readout that could not be produced.
///
/// These are the refusals a headless surface has to make before it has any numbers to show: the store
/// is not usable, no airport was chosen, or the airport or runway is not in the database. A surface
/// that speaks its answer aloud must be able to say why it has none.
public enum PerformanceLookupError: Error {
  /// The nav database was written by a different version of the app and has not been reimported.
  case navigationDataOutOfDate

  /// Neither the request nor the app's own settings named an airport.
  case noAirportSelected

  /// The named airport is not in the database.
  case airportNotFound

  /// Neither the request nor the app's own settings named a runway.
  case noRunwaySelected

  /// The airport has no runway with the requested name.
  case runwayNotFound(name: String, airport: String)

  /// Weather could not be loaded, so there is nothing to calculate from.
  case weatherUnavailable(airport: String)
}
