import CoreLocation
import NavData

/// Protocol for items with a geographic location.
public protocol Locatable {
  var coordinate: CLLocationCoordinate2D { get }
}

/// Finds items near a geographic location using two-stage filtering.
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

  /// Finds items within radius using two-stage filtering:
  /// 1. Rough bounding box filter (fast, for pre-filtering large datasets)
  /// 2. Precise Haversine distance calculation and sorting
  ///
  /// - Parameters:
  ///   - coordinate: Center point
  ///   - items: Items to search (already filtered by bounding box if from database)
  ///   - radiusNM: Maximum distance in nautical miles
  ///   - limit: Maximum results to return
  /// - Returns: Items sorted by distance, closest first
  public static func find<T: Locatable>(
    near coordinate: CLLocationCoordinate2D,
    in items: [T],
    radiusNM: Double,
    limit: Int = 10
  ) -> [(item: T, distanceNM: Double)] {
    // Stage 1: Bounding box filter (if not already filtered at database level)
    // Use 15% margin to account for longitude convergence at different latitudes
    let bounds = boundingBox(center: coordinate, radiusNM: radiusNM * 1.15)
    let candidates = items.filter { item in
      item.coordinate.latitude >= bounds.minLat
        && item.coordinate.latitude <= bounds.maxLat
        && item.coordinate.longitude >= bounds.minLon
        && item.coordinate.longitude <= bounds.maxLon
    }

    // Stage 2: Precise distance calculation and sorting
    return
      candidates
      .map {
        (item: $0, distanceNM: GeoCalculations.distanceNM(from: coordinate, to: $0.coordinate))
      }
      .filter { $0.distanceNM <= radiusNM }
      .sorted { $0.distanceNM < $1.distanceNM }
      .prefix(limit)
      .map(\.self)
  }
}

// MARK: - Conformances for existing types

extension Airport: Locatable {}
extension Obstacle: Locatable {}
