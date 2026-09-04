import CoreLocation
import Foundation
import Logging

extension WeatherLoader {
  /// How far a station may sit from an airport and still be taken as that airport’s own report.
  ///
  /// The NWS names each forecast location by its FAA or VOR identifier, but frequently forecasts
  /// for the VOR rather than the field: `DEN` is 10 NM from Denver International and `MSP` is
  /// 16 NM from Minneapolis-St Paul. Matching identifiers alone would accept a collision — an
  /// airport whose location ID happens to equal an oceanic grid point such as `4J3` — and
  /// ``Airport/locationID`` is not reliably the FAA identifier in the first place. Confirming the
  /// match by position rejects those while leaving room for the widest genuine pairing, which is
  /// 21 NM.
  static let reportingStationRadiusNM: Double = 50

  /// The loaded bulletin the NWS publishes for use at a given time.
  ///
  /// A time no bulletin covers has no winds aloft forecast: the published use periods are the
  /// only times a forecast applies to.
  ///
  /// - Parameters:
  ///   - time: The time winds aloft are needed for.
  ///   - bulletins: The loaded bulletins, ordered by valid time.
  /// - Returns: The bulletins covering `time`, ordered by valid time.
  static func bulletins(for time: Date, in bulletins: [WindsAloftBulletin]) -> [WindsAloftBulletin]
  {
    bulletins.filter { $0.usePeriod.contains(time) }
  }

  /// Gets winds aloft for a key, from its own reporting station or interpolated between others.
  static func stationData(
    for key: Key,
    in bulletin: WindsAloftBulletin
  ) -> (source: WindsAloftForecast.Source, data: WindsAloftData)? {
    reportedData(
      stationID: key.windsAloftID,
      at: key.location.coordinate,
      in: bulletin
    ) ?? WindsAloftInterpolator.interpolate(at: key.location.coordinate, in: bulletin)
  }

  /// Gets the data for an airport’s own reporting station, if it has one.
  ///
  /// The identifier must resolve to a known forecast location near the airport; see
  /// ``reportingStationRadiusNM``. A station the table doesn’t know is logged rather than trusted,
  /// since the NWS revising its list is the one thing that invalidates the bundled table.
  ///
  /// - Parameters:
  ///   - stationID: The airport’s FAA location identifier.
  ///   - coordinate: Where the airport is.
  ///   - bulletin: The bulletin to look the station up in.
  /// - Returns: The station’s data, or `nil` if the airport has no station of its own.
  static func reportedData(
    stationID: String,
    at coordinate: CLLocationCoordinate2D,
    in bulletin: WindsAloftBulletin
  ) -> (source: WindsAloftForecast.Source, data: WindsAloftData)? {
    guard let data = bulletin.stations[stationID] else { return nil }

    guard let station = WindsAloftStation.all[stationID] else {
      logger.warning(
        "Winds aloft bulletin reports a station missing from the bundled table",
        metadata: ["station": "\(stationID)"]
      )
      return nil
    }

    let distanceNM = GeoCalculations.distanceNM(from: coordinate, to: station.coordinate)
    guard distanceNM <= reportingStationRadiusNM else { return nil }

    return (.station(stationID), data)
  }

  /// Gets the winds aloft forecast for a key, or `nil` if no service has one for its time
  /// and place.
  ///
  /// The NWS bulletins are authoritative and answer first. They cover the United States and forecast
  /// about a day out, so a departure from elsewhere — or further ahead than they reach — falls to
  /// Open-Meteo's pressure levels instead of flying through calm air. Their own coverage decides
  /// this rather than a boundary drawn here: the bulletins yield nothing exactly when no published
  /// period covers the time and no station lies near enough to interpolate from.
  ///
  /// A key neither service can answer reports a partly failed bulletin download, if there was one:
  /// the bulletin covering it may simply be one that didn’t arrive, which is worth a retry, unlike
  /// a time and place nothing is published for.
  func windsAloftForecast(for key: Key) async -> Loadable<WindsAloftForecast?> {
    let bulletinForecast = bulletinForecast(for: key)
    guard case .value(let forecast) = bulletinForecast else { return bulletinForecast }
    if let forecast { return .value(forecast) }
    if let forecast = await openMeteoForecast(for: key) { return .value(forecast) }
    if let windsAloftPartialFailure { return .error(windsAloftPartialFailure) }
    return .value(nil)
  }

  /// Gets the NWS bulletin forecast for a key, or `nil` if none covers its time and place.
  private func bulletinForecast(for key: Key) -> Loadable<WindsAloftForecast?> {
    windsAloft.map { bulletins in
      // Regions covering the same period are merged, so normally one bulletin covers a time.
      // Should a region ever publish a period of its own, the first bulletin covering the time
      // might not be the one carrying this airport's part of the country.
      Self.bulletins(for: key.time, in: bulletins)
        .lazy
        .compactMap { bulletin -> WindsAloftForecast? in
          guard let data = Self.stationData(for: key, in: bulletin) else { return nil }
          return .init(
            validAt: bulletin.validAt,
            usePeriod: bulletin.usePeriod,
            source: data.source,
            data: data.data
          )
        }
        .first
    }
  }

  /// Gets Open-Meteo's winds aloft for a key, or `nil` if it has none or couldn't be reached.
  ///
  /// A model that can't be reached leaves the flight without winds aloft rather than failing the
  /// lookup, so the failure is recorded and swallowed.
  private func openMeteoForecast(for key: Key) async -> WindsAloftForecast? {
    do {
      return try await OpenMeteoService.shared.windsAloft(for: key)
    } catch {
      Self.recordLoadFailure(error, dataType: "openMeteo", airport: key.id)
      return nil
    }
  }
}
