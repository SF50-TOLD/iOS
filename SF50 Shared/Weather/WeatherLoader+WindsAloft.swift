import CoreLocation
import Foundation

extension WeatherLoader {
  /// The loaded bulletin the NWS publishes for use at a given time.
  ///
  /// A time no bulletin covers has no winds aloft forecast: the published use periods are the
  /// only times a forecast applies to.
  ///
  /// - Parameters:
  ///   - time: The time winds aloft are needed for.
  ///   - bulletins: The loaded bulletins, ordered by valid time.
  /// - Returns: The bulletin covering `time`, or `nil` if none does.
  static func bulletin(for time: Date, in bulletins: [WindsAloftBulletin]) -> WindsAloftBulletin? {
    bulletins.first { $0.usePeriod.contains(time) }
  }

  /// Gets the winds aloft forecast for a key, or `nil` if none covers its time.
  func windsAloftForecast(for key: Key) -> Loadable<WindsAloftForecast?> {
    windsAloft.map { bulletins in
      guard let bulletin = Self.bulletin(for: key.time, in: bulletins),
        let data = stationData(for: key, in: bulletin)
      else { return nil }

      return .init(validAt: bulletin.validAt, usePeriod: bulletin.usePeriod, data: data)
    }
  }

  /// Gets station data for a key, falling back to spatial interpolation if needed.
  private func stationData(for key: Key, in bulletin: WindsAloftBulletin) -> WindsAloftData? {
    // First try direct lookup
    if let directData = bulletin.stations[key.windsAloftID] {
      return directData
    }

    // Fall back to spatial interpolation
    guard !stationLocations.isEmpty else { return nil }

    let locatedStations: [WindsAloftInterpolator.LocatedStation] = bulletin.stations.compactMap {
      stationID,
      data in
      guard let location = stationLocations[stationID] else { return nil }
      return WindsAloftInterpolator.LocatedStation(
        stationID: stationID,
        coordinate: location,
        data: data
      )
    }

    guard !locatedStations.isEmpty else { return nil }

    let coordinate = key.location.coordinate

    // Find nearby stations to determine which altitudes to interpolate
    let nearbyStations = NearbyFinder.find(
      near: coordinate,
      in: locatedStations,
      radius: WindsAloftInterpolator.Configuration.default.maxDistance,
      limit: WindsAloftInterpolator.Configuration.default.maxStations
    )

    guard !nearbyStations.isEmpty else { return nil }

    // Collect all unique altitudes from nearby stations
    let allAltitudes: Set<Double> = nearbyStations.reduce(into: []) { result, station in
      for entry in station.item.data.entries {
        result.insert(entry.altitude.converted(to: .feet).value)
      }
    }

    // Interpolate at each available altitude
    let entries: [WindsAloftData.Entry] = allAltitudes.sorted().compactMap { altitude in
      WindsAloftInterpolator.interpolate(
        at: coordinate,
        altitude: .init(value: altitude, unit: .feet),
        from: locatedStations
      )
    }

    guard !entries.isEmpty else { return nil }

    // Create synthetic WindsAloftData
    return WindsAloftData(
      stationID: "INTERPOLATED",
      entries: entries
    )
  }
}
