import CoreLocation
import Foundation

/// A flight path enriched with terrain elevation and obstacle data per point.
///
/// Combines the aircraft position and altitude from ``ProcedurePath`` with
/// terrain and obstacle information within a lateral corridor, suitable for
/// rendering a terrain profile cross-section view.
public struct ProcedureTerrainPath: Sendable {
  /// Half-width of the lateral corridor used for terrain and obstacle sampling, in nautical miles.
  public let corridorWidthNM: Double

  /// Path points with combined flight profile, terrain, and obstacle data.
  public let points: [Point]

  /// True when terrain elevation data is available for every point along the path.
  /// After ocean-fill in the generator, remaining nils indicate undownloaded regions.
  public var terrainDataAvailable: Bool {
    !points.contains { $0.terrainElevationFt == nil }
  }

  /// True when the entire path falls within the FAA DOF obstacle survey area.
  public var obstacleDataAvailable: Bool {
    points.allSatisfy { ObstacleSurveyRegion.contains(coordinate: $0.coordinate) }
  }

  /// Geographic coordinates of all path points.
  public var coordinates: [CLLocationCoordinate2D] { points.map(\.coordinate) }

  /// Total path distance in nautical miles.
  public var totalDistanceNM: Double { points.last?.distanceNM ?? 0 }

  /// A single point along the terrain-enriched path.
  public struct Point: Sendable {
    /// Geographic coordinate of this path point.
    public let coordinate: CLLocationCoordinate2D
    /// Cumulative distance in nautical miles from the path origin.
    public let distanceNM: Double
    /// Computed aircraft altitude in feet MSL at this point.
    public let aircraftAltitudeFt: Double
    /// Altitude restriction at this point, if any.
    public let altitudeRestriction: AltitudeRestriction?
    /// Fix/waypoint name at this point, if any.
    public let fixName: String?
    /// Maximum terrain elevation in feet MSL within the corridor at this point,
    /// or nil if no terrain data is available.
    public let terrainElevationFt: Double?
    /// Height in feet MSL of the tallest obstacle within the corridor at this point,
    /// or nil if no obstacle was found.
    public let maxObstacleHeightFt: Double?
  }
}
