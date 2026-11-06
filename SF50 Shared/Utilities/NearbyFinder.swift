public import CoreLocation

/// Bounding-box math for finding items near a geographic location.
public enum NearbyFinder {

  /// Calculates bounding box coordinates for a given center and radius.
  ///
  /// Uses the approximations:
  /// - 1 degree latitude ≈ 60 nautical miles
  /// - Longitude delta varies with latitude (accounts for convergence at poles)
  ///
  /// - Parameters:
  ///   - center: Center coordinate
  ///   - radiusNM: Radius in nautical miles
  /// - Returns: Tuple of (minLat, maxLat, minLon, maxLon)
  public static func boundingBox(
    center: CLLocationCoordinate2D,
    radiusNM: Double
  ) -> (minLat: Double, maxLat: Double, minLon: Double, maxLon: Double) {
    // 1 degree latitude ≈ 60 nautical miles
    let latDelta = radiusNM / 60.0
    // Longitude delta varies with latitude
    let cosLat = cos(center.latitude * .pi / 180.0)
    let lonDelta = cosLat > 0.001 ? radiusNM / (60.0 * cosLat) : 180.0
    return (
      minLat: center.latitude - latDelta,
      maxLat: center.latitude + latDelta,
      minLon: center.longitude - lonDelta,
      maxLon: center.longitude + lonDelta
    )
  }
}
