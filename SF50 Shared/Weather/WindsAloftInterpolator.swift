import CoreLocation

/// Interpolates winds aloft data from multiple stations using Inverse Distance Weighting (IDW).
public enum WindsAloftInterpolator {

  // MARK: - Public Methods

  /// Interpolates winds aloft for a target location and altitude.
  ///
  /// Uses Inverse Distance Weighting (IDW) to combine data from nearby stations.
  /// Wind direction is averaged using unit vectors to handle circular nature.
  ///
  /// - Parameters:
  ///   - coordinate: Target location
  ///   - altitude: Target altitude
  ///   - stations: Available winds aloft stations with locations
  ///   - configuration: Interpolation parameters
  /// - Returns: Interpolated entry, or `nil` if insufficient nearby stations
  public static func interpolate(
    at coordinate: CLLocationCoordinate2D,
    altitude: Measurement<UnitLength>,
    from stations: [LocatedStation],
    configuration: Configuration = .default
  ) -> WindsAloftData.Entry? {
    // Find nearby stations
    let nearby = NearbyFinder.find(
      near: coordinate,
      in: stations,
      radius: configuration.maxDistance,
      limit: configuration.maxStations
    )

    guard !nearby.isEmpty else { return nil }

    // If closest station is very close, use it directly
    if let closest = nearby.first, closest.distanceNM < configuration.directUseThreshold {
      return closest.item.data.entry(at: altitude)
    }

    // Need minimum stations for interpolation
    guard nearby.count >= configuration.minStations else {
      // Use single station if available
      return nearby.first?.item.data.entry(at: altitude)
    }

    // Get altitude-interpolated entries from each station
    let stationEntries: [(entry: WindsAloftData.Entry, distanceNM: Double)] = nearby.compactMap {
      station in
      guard let entry = station.item.data.entry(at: altitude) else { return nil }
      return (entry, station.distanceNM)
    }

    guard stationEntries.count >= configuration.minStations else {
      return stationEntries.first?.entry
    }

    return idwInterpolate(entries: stationEntries, altitude: altitude, power: configuration.power)
  }

  // MARK: - Private Methods

  /// Performs IDW interpolation on a set of station entries.
  private static func idwInterpolate(
    entries: [(entry: WindsAloftData.Entry, distanceNM: Double)],
    altitude: Measurement<UnitLength>,
    power: Double
  ) -> WindsAloftData.Entry {
    // Calculate weights: wi = 1 / di^power
    let weights = entries.map { 1.0 / pow(max($0.distanceNM, 0.001), power) }
    let totalWeight = weights.reduce(0, +)

    // Interpolate wind speed
    var weightedSpeed = 0.0
    for (i, stationEntry) in entries.enumerated() {
      let speed = stationEntry.entry.windSpeed.converted(to: .knots).value
      weightedSpeed += weights[i] * speed
    }
    let interpolatedSpeed = weightedSpeed / totalWeight

    // Interpolate wind direction using unit vectors
    var sumX = 0.0,
      sumY = 0.0
    var hasValidDirection = false
    for (i, stationEntry) in entries.enumerated() {
      if let direction = stationEntry.entry.windDirection?.converted(to: .degrees).value {
        let radians = direction * .pi / 180.0
        sumX += weights[i] * sin(radians)
        sumY += weights[i] * cos(radians)
        hasValidDirection = true
      }
    }

    let interpolatedDirection: Measurement<UnitAngle>?
    if hasValidDirection {
      var directionDegrees = atan2(sumX, sumY) * 180.0 / .pi
      if directionDegrees < 0 { directionDegrees += 360.0 }
      interpolatedDirection = .init(value: directionDegrees, unit: .degrees)
    } else {
      interpolatedDirection = nil
    }

    // Interpolate temperature
    var weightedTemp = 0.0,
      tempWeight = 0.0
    for (i, stationEntry) in entries.enumerated() {
      if let temp = stationEntry.entry.temperature?.converted(to: .celsius).value {
        weightedTemp += weights[i] * temp
        tempWeight += weights[i]
      }
    }
    let interpolatedTemp: Measurement<UnitTemperature>?
    if tempWeight > 0 {
      interpolatedTemp = .init(value: weightedTemp / tempWeight, unit: .celsius)
    } else {
      interpolatedTemp = nil
    }

    return WindsAloftData.Entry(
      altitude: altitude,
      windDirection: interpolatedDirection,
      windSpeed: .init(value: interpolatedSpeed, unit: .knots),
      temperature: interpolatedTemp
    )
  }

  // MARK: - Subtypes

  /// Configuration for spatial interpolation.
  public struct Configuration: Sendable {
    public static let `default` = Self()

    public var maxDistance: Double
    public var minStations: Int
    public var maxStations: Int
    public var power: Double
    public var directUseThreshold: Double

    /// Creates a configuration for spatial interpolation.
    ///
    /// - Parameters:
    ///   - maxDistance: Maximum distance to consider stations (nautical miles). Default: 150.
    ///   - minStations: Minimum stations required for interpolation. Default: 2.
    ///   - maxStations: Maximum stations to use. Default: 4.
    ///   - power: IDW power parameter (higher = more weight to closer stations). Default: 2.
    ///   - directUseThreshold: Distance below which a single station is used directly (nm). Default: 5.
    public init(
      maxDistance: Double = 150.0,
      minStations: Int = 2,
      maxStations: Int = 4,
      power: Double = 2.0,
      directUseThreshold: Double = 5.0
    ) {
      self.maxDistance = maxDistance
      self.minStations = minStations
      self.maxStations = maxStations
      self.power = power
      self.directUseThreshold = directUseThreshold
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
