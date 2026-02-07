import CoreLocation
import Foundation

/// Shared geographic calculation utilities.
public enum GeoCalculations {
  /// Shared Geomagnetism instance for calculating magnetic variation.
  /// Reused to avoid expensive initialization on each calculation.
  /// Note: nonisolated(unsafe) is used because Geomagnetism doesn't conform to Sendable,
  /// but in practice it's used safely with temporary instance state.
  nonisolated(unsafe) private static let geomagnetism = Geomagnetism()

  /// Calculates bearing between two points specified in arcseconds.
  /// - Parameters:
  ///   - from: Tuple of (latitude, longitude) in arcseconds
  ///   - to: Tuple of (latitude, longitude) in arcseconds
  /// - Returns: Bearing in degrees (0-360)
  public static func calculateBearing(from: (Float, Float), to: (Float, Float)) -> Float {
    let lat1 = from.0 / 3600 * .pi / 180,
      lat2 = to.0 / 3600 * .pi / 180,
      deltaLon = (to.1 / 3600 - from.1 / 3600) * .pi / 180

    let x = sin(deltaLon) * cos(lat2),
      y = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLon)

    let bearing = atan2(x, y) * 180 / .pi
    return (bearing + 360).truncatingRemainder(dividingBy: 360)
  }

  /// Calculates magnetic variation using the WMM model.
  /// - Parameters:
  ///   - latitudeDeg: Latitude in decimal degrees
  ///   - longitudeDeg: Longitude in decimal degrees
  /// - Returns: Magnetic declination in degrees (positive = east)
  public static func calculateMagneticVariation(_ latitudeDeg: Double, _ longitudeDeg: Double)
    -> Double
  {
    geomagnetism.calculate(longitude: longitudeDeg, latitude: latitudeDeg)
    return geomagnetism.declination
  }

  /// Calculates distance in nautical miles between two coordinates using the Haversine formula.
  /// - Parameters:
  ///   - fromLat: Origin latitude in decimal degrees
  ///   - fromLon: Origin longitude in decimal degrees
  ///   - toLat: Destination latitude in decimal degrees
  ///   - toLon: Destination longitude in decimal degrees
  /// - Returns: Distance in nautical miles
  public static func calculateDistanceNM(
    fromLat: Double,
    fromLon: Double,
    toLat: Double,
    toLon: Double
  ) -> Double {
    let lat1 = fromLat * .pi / 180,
      lat2 = toLat * .pi / 180,
      deltaLat = (toLat - fromLat) * .pi / 180,
      deltaLon = (toLon - fromLon) * .pi / 180

    // Haversine formula
    let a =
      sin(deltaLat / 2) * sin(deltaLat / 2)
      + cos(lat1) * cos(lat2) * sin(deltaLon / 2) * sin(deltaLon / 2)
    let c = 2 * atan2(sqrt(a), sqrt(1 - a))

    return earthRadiusNM * c
  }

  /// Calculates distance in nautical miles between two coordinates.
  /// - Parameters:
  ///   - from: Origin coordinate
  ///   - to: Destination coordinate
  /// - Returns: Distance in nautical miles
  public static func distanceNM(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double
  {
    calculateDistanceNM(
      fromLat: from.latitude,
      fromLon: from.longitude,
      toLat: to.latitude,
      toLon: to.longitude
    )
  }

  /// Interpolates between two coordinates.
  /// - Parameters:
  ///   - from: Origin coordinate
  ///   - to: Destination coordinate
  ///   - fraction: Fraction of the distance (0.0 = from, 1.0 = to)
  /// - Returns: Interpolated coordinate
  public static func interpolate(
    from: CLLocationCoordinate2D,
    to: CLLocationCoordinate2D,
    fraction: Double
  ) -> CLLocationCoordinate2D {
    // Simple linear interpolation (accurate enough for short distances)
    let lat = from.latitude + (to.latitude - from.latitude) * fraction
    let lon = from.longitude + (to.longitude - from.longitude) * fraction
    return CLLocationCoordinate2D(latitude: lat, longitude: lon)
  }

  /// Calculates the initial bearing from one coordinate to another.
  ///
  /// Uses the forward azimuth formula on a spherical Earth.
  ///
  /// - Parameters:
  ///   - from: Starting coordinate.
  ///   - to: Destination coordinate.
  /// - Returns: The initial bearing as a Measurement in degrees (0-360).
  public static func bearing(
    from start: CLLocationCoordinate2D,
    to end: CLLocationCoordinate2D
  ) -> Measurement<UnitAngle> {
    let lat1 = start.latitude * .pi / 180
    let lat2 = end.latitude * .pi / 180
    let deltaLon = (end.longitude - start.longitude) * .pi / 180

    let x = sin(deltaLon) * cos(lat2)
    let y = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLon)

    let bearingRadians = atan2(x, y)
    let bearingDegrees = (bearingRadians * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)

    return .init(value: bearingDegrees, unit: .degrees)
  }

  /// Computes ground track and ground speed from the wind triangle.
  ///
  /// - Parameters:
  ///   - trueHeading: Aircraft true heading (direction nose points)
  ///   - tasKnots: True airspeed in knots
  ///   - windFromTrue: Direction wind blows FROM (true north ref)
  ///   - windSpeedKnots: Wind speed in knots
  /// - Returns: (groundTrack: degrees true 0-360, groundSpeedKnots: Double)
  public static func windTriangle(
    trueHeading: Measurement<UnitAngle>,
    tasKnots: Double,
    windFromTrue: Measurement<UnitAngle>,
    windSpeedKnots: Double
  ) -> (groundTrack: Measurement<UnitAngle>, groundSpeedKnots: Double) {
    let thRad = trueHeading.converted(to: .radians).value
    let wdRad = windFromTrue.converted(to: .radians).value

    // Aircraft air velocity
    let airEast = tasKnots * sin(thRad)
    let airNorth = tasKnots * cos(thRad)

    // Wind pushes opposite to FROM direction
    let windEast = -windSpeedKnots * sin(wdRad)
    let windNorth = -windSpeedKnots * cos(wdRad)

    // Ground velocity
    let gsEast = airEast + windEast
    let gsNorth = airNorth + windNorth

    let groundSpeed = (gsEast * gsEast + gsNorth * gsNorth).squareRoot()
    let trackRad = atan2(gsEast, gsNorth)
    let trackDeg = (trackRad * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)

    return (
      groundTrack: .init(value: trackDeg, unit: .degrees),
      groundSpeedKnots: groundSpeed
    )
  }

  /// Calculates a destination coordinate given a starting point, distance, and bearing.
  ///
  /// Uses the Haversine formula on a spherical Earth.
  ///
  /// - Parameters:
  ///   - from: Starting coordinate.
  ///   - distance: Distance to travel.
  ///   - bearing: True bearing in degrees (0-360).
  /// - Returns: The destination coordinate.
  public static func destination(
    from start: CLLocationCoordinate2D,
    distance: Measurement<UnitLength>,
    bearing: Measurement<UnitAngle>
  ) -> CLLocationCoordinate2D {
    let distanceMeters = distance.converted(to: .meters).value
    let bearingRadians = bearing.converted(to: .radians).value

    let lat1 = start.latitude * .pi / 180
    let lon1 = start.longitude * .pi / 180

    let angularDistance = distanceMeters / earthRadiusMeters

    let lat2 = asin(
      sin(lat1) * cos(angularDistance)
        + cos(lat1) * sin(angularDistance) * cos(bearingRadians)
    )

    let lon2 =
      lon1
      + atan2(
        sin(bearingRadians) * sin(angularDistance) * cos(lat1),
        cos(angularDistance) - sin(lat1) * sin(lat2)
      )

    return CLLocationCoordinate2D(
      latitude: lat2 * 180 / .pi,
      longitude: lon2 * 180 / .pi
    )
  }
}
