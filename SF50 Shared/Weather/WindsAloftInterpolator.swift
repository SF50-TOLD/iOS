import CoreLocation
import Foundation

/// Interpolates winds aloft between reporting stations using Inverse Distance Weighting (IDW).
///
/// Most airports are not themselves forecast locations — the NWS publishes 233 of them — so their
/// winds aloft are interpolated from the stations around them. NWS Instruction 10-812 §3 provides
/// for this directly: "Forecasts for intermediate locations may be determined by interpolation."
public enum WindsAloftInterpolator {

  // MARK: - Public Methods

  /// Interpolates a wind and temperature column for a location from the stations around it.
  ///
  /// - Parameters:
  ///   - coordinate: The location to interpolate for.
  ///   - bulletin: The bulletin to draw stations from.
  ///   - configuration: Interpolation parameters.
  /// - Returns: The interpolated column and where it came from, or `nil` if no station is near
  ///   enough.
  static func interpolate(
    at coordinate: CLLocationCoordinate2D,
    in bulletin: WindsAloftBulletin,
    configuration: Configuration = .default
  ) -> (source: WindsAloftForecast.Source, data: WindsAloftData)? {
    let located = bulletin.stations.compactMap { stationID, data -> LocatedStation? in
      guard let station = WindsAloftStation.all[stationID] else { return nil }
      return .init(stationID: stationID, coordinate: station.coordinate, data: data)
    }

    let nearby = NearbyFinder.find(
      near: coordinate,
      in: located,
      radiusNM: configuration.maxDistanceNM,
      limit: configuration.maxStations
    )
    guard let closest = nearby.first else { return nil }

    // A station this close is the forecast for this location, not a neighbour of it.
    if closest.distanceNM < configuration.directUseThresholdNM {
      return (.station(closest.item.stationID), closest.item.data)
    }

    let entries = interpolate(neighbors: nearby, configuration: configuration)
    guard !entries.isEmpty else { return nil }

    return (.interpolated, .init(entries: entries))
  }

  /// Interpolates a location's winds aloft at a single altitude.
  ///
  /// - Parameters:
  ///   - coordinate: The location to interpolate for.
  ///   - altitude: The altitude to interpolate at.
  ///   - stations: The stations available to draw from.
  ///   - configuration: Interpolation parameters.
  /// - Returns: The interpolated entry, or `nil` if no station near enough covers that altitude.
  public static func interpolate(
    at coordinate: CLLocationCoordinate2D,
    altitude: Measurement<UnitLength>,
    from stations: [LocatedStation],
    configuration: Configuration = .default
  ) -> WindsAloftData.Entry? {
    let nearby = NearbyFinder.find(
      near: coordinate,
      in: stations,
      radiusNM: configuration.maxDistanceNM,
      limit: configuration.maxStations
    )
    guard let closest = nearby.first else { return nil }

    if closest.distanceNM < configuration.directUseThresholdNM {
      return closest.item.data.entry(at: altitude)
    }

    return interpolate(neighbors: nearby, at: altitude, configuration: configuration)
  }

  // MARK: - Private Methods

  /// Interpolates a full column at every altitude the neighbouring stations publish.
  private static func interpolate(
    neighbors: [(item: LocatedStation, distanceNM: Double)],
    configuration: Configuration
  ) -> [WindsAloftData.Entry] {
    let altitudes = Set(neighbors.flatMap { $0.item.data.entries.map(\.altitude) })

    return
      altitudes
      .sorted()
      .compactMap { interpolate(neighbors: neighbors, at: $0, configuration: configuration) }
  }

  /// Interpolates one altitude from the neighbouring stations that publish it.
  ///
  /// A station only contributes at altitudes it actually reports. The bulletin omits levels within
  /// 1,500 feet of a station's elevation, so a station on high terrain may start at 9,000 or 12,000
  /// feet; ``WindsAloftData/entry(at:)`` clamps below its lowest level, which would otherwise let
  /// that station's 9,000-foot wind stand in for the wind at 3,000 feet.
  ///
  /// Too few stations to blend, or neighbours whose winds cancel, both fall back to the nearest
  /// station's own forecast — the closest thing to an answer there is at that level.
  private static func interpolate(
    neighbors: [(item: LocatedStation, distanceNM: Double)],
    at altitude: Measurement<UnitLength>,
    configuration: Configuration
  ) -> WindsAloftData.Entry? {
    let covering = neighbors.compactMap {
      neighbor -> (entry: WindsAloftData.Entry, distanceNM: Double)? in
      guard neighbor.item.data.covers(altitude: altitude),
        let entry = neighbor.item.data.entry(at: altitude)
      else { return nil }
      return (entry, neighbor.distanceNM)
    }

    guard covering.count >= configuration.minStations else { return covering.first?.entry }

    return idwInterpolate(entries: covering, altitude: altitude, power: configuration.power)
      ?? covering.first?.entry
  }

  /// Combines station entries by inverse-distance-weighting their wind vectors.
  ///
  /// Wind is averaged as a vector rather than as a speed and a direction separately, which is both
  /// the standard treatment and the only self-consistent one: opposing winds settle to a light
  /// resultant instead of retaining their full speed on an arbitrary heading. Light and variable
  /// entries carry no direction and contribute nothing, which is what a calm station should do.
  ///
  /// - Returns: The blended entry, or `nil` if the neighbours' winds cancel: a resultant left over
  ///   from stations that are themselves blowing hard is unresolved rather than calm, and reporting
  ///   it as calm would be indistinguishable from a station forecasting light and variable.
  private static func idwInterpolate(
    entries: [(entry: WindsAloftData.Entry, distanceNM: Double)],
    altitude: Measurement<UnitLength>,
    power: Double
  ) -> WindsAloftData.Entry? {
    var northward = 0.0,
      eastward = 0.0,
      weightedSpeed = 0.0,
      totalWeight = 0.0
    var weightedTemperature = 0.0,
      temperatureWeight = 0.0

    for (entry, distanceNM) in entries {
      let weight = 1 / pow(max(distanceNM, Self.minimumDistanceNM), power)
      totalWeight += weight

      if let direction = entry.windDirection?.converted(to: .degrees).value {
        let radians = direction * .pi / 180,
          speed = entry.windSpeed.converted(to: .knots).value
        eastward += weight * speed * sin(radians)
        northward += weight * speed * cos(radians)
        weightedSpeed += weight * speed
      }

      if let temperature = entry.temperature?.converted(to: .celsius).value {
        weightedTemperature += weight * temperature
        temperatureWeight += weight
      }
    }

    let resultantSpeed = hypot(eastward, northward) / totalWeight,
      meanSpeed = weightedSpeed / totalWeight
    let isCalm = resultantSpeed < Self.calmThresholdKts
    guard !isCalm || meanSpeed < Self.calmThresholdKts else { return nil }

    return .init(
      altitude: altitude,
      windDirection: isCalm
        ? nil
        : .init(value: compassDegrees(eastward: eastward, northward: northward), unit: .degrees),
      windSpeed: .init(value: isCalm ? 0 : resultantSpeed, unit: .knots),
      temperature: temperatureWeight > 0
        ? .init(value: weightedTemperature / temperatureWeight, unit: .celsius)
        : nil
    )
  }

  /// The compass bearing of a wind vector, normalized to 0..<360.
  private static func compassDegrees(eastward: Double, northward: Double) -> Double {
    let degrees = atan2(eastward, northward) * 180 / .pi
    return degrees < 0 ? degrees + 360 : degrees
  }

  // MARK: - Subtypes

  /// Configuration for spatial interpolation.
  public struct Configuration: Sendable {
    public static let `default` = Self()

    public var maxDistanceNM: Double
    public var minStations: Int
    public var maxStations: Int
    public var power: Double
    public var directUseThresholdNM: Double

    /// Creates a configuration for spatial interpolation.
    ///
    /// - Parameters:
    ///   - maxDistanceNM: Maximum distance to consider stations (nautical miles). Default: 150.
    ///   - minStations: Minimum stations required for interpolation. Default: 2.
    ///   - maxStations: Maximum stations to use. Default: 4.
    ///   - power: IDW power parameter (higher = more weight to closer stations). Default: 2.
    ///   - directUseThresholdNM: Distance below which a single station is used directly, in
    ///     nautical miles. Default: 5.
    public init(
      maxDistanceNM: Double = 150.0,
      minStations: Int = 2,
      maxStations: Int = 4,
      power: Double = 2.0,
      directUseThresholdNM: Double = 5.0
    ) {
      self.maxDistanceNM = maxDistanceNM
      self.minStations = minStations
      self.maxStations = maxStations
      self.power = power
      self.directUseThresholdNM = directUseThresholdNM
    }
  }

  /// A winds aloft station with its geographic location.
  public struct LocatedStation: Sendable, Locatable {
    public let stationID: String
    public let coordinate: CLLocationCoordinate2D
    public let data: WindsAloftData

    public init(stationID: String, coordinate: CLLocationCoordinate2D, data: WindsAloftData) {
      self.stationID = stationID
      self.coordinate = coordinate
      self.data = data
    }
  }
}

// MARK: - Constants

extension WindsAloftInterpolator {
  /// Keeps a station at the interpolation point itself from carrying infinite weight.
  private static let minimumDistanceNM = 0.001

  /// The speed below which a resultant wind is reported as light and variable rather than given a
  /// direction, matching how the bulletins themselves encode calm winds.
  private static let calmThresholdKts = 0.5
}
