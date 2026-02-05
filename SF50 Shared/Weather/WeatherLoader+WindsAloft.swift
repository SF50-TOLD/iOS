import CoreLocation
import Foundation

extension WeatherLoader {
  /// Gets winds aloft data for a key, falling back to spatial interpolation if needed.
  func windsAloftData(for key: Key) -> Loadable<WindsAloftData?> {
    windsAloft.map { stationData in
      // First try direct lookup
      if let directData = stationData[key.windsAloftID] {
        return directData
      }

      // Fall back to spatial interpolation
      guard !stationLocations.isEmpty else { return nil }

      let locatedStations: [WindsAloftInterpolator.LocatedStation] = stationData.compactMap {
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
}
