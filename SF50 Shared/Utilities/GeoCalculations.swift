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
}
