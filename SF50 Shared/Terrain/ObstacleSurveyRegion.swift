import CoreLocation
import Foundation

/// Approximate bounding boxes for the FAA Digital Obstacle File (DOF) survey area.
///
/// The FAA states the DOF has "limited coverage of the Pacific, the Caribbean,
/// Canada, and Mexico" but publishes no formal survey boundaries. These boxes
/// approximate US sovereign territory.
public enum ObstacleSurveyRegion {
  private static let boundingBoxes: [TerrainBoundingBox] = [
    .init(minLat: 24, maxLat: 50, minLon: -125, maxLon: -66),  // CONUS
    .init(minLat: 50, maxLat: 72, minLon: -180, maxLon: -130),  // Alaska mainland
    .init(minLat: 50, maxLat: 56, minLon: 170, maxLon: 180),  // Aleutians (past date line)
    .init(minLat: 18, maxLat: 23, minLon: -161, maxLon: -154),  // Hawaii
    .init(minLat: 17, maxLat: 19, minLon: -68, maxLon: -64),  // Puerto Rico & USVI
    .init(minLat: 13, maxLat: 21, minLon: 144, maxLon: 146),  // Guam & CNMI
    .init(minLat: -15, maxLat: -13, minLon: -171, maxLon: -169)  // American Samoa
  ]

  /// Whether the given coordinate falls within the FAA DOF survey area.
  public static func contains(coordinate: CLLocationCoordinate2D) -> Bool {
    boundingBoxes.contains {
      $0.contains(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
  }
}
