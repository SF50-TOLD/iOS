public import CoreLocation
public import Foundation

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

  /// The highest altitude the path reaches, whether aircraft or terrain.
  ///
  /// Terrain below the field is read as being at the field: a profile is drawn from the runway
  /// upwards, so a valley beside it is not what sets the scale.
  ///
  /// - Parameter fieldElevation: The elevation of the airport.
  /// - Returns: The altitude the profile reaches.
  public func maxAltitude(fieldElevation: Measurement<UnitLength>) -> Measurement<UnitLength> {
    let fieldElevationFt = fieldElevation.converted(to: .feet).value
    let maxAircraft = points.map(\.aircraftAltitudeFt).max() ?? fieldElevationFt
    let maxTerrain =
      points.map { $0.drawnTerrainElevationFt(fieldElevationFt: fieldElevationFt) }.max()
      ?? fieldElevationFt
    return .init(value: max(maxAircraft, maxTerrain), unit: .feet)
  }

  /// The sample nearest a distance along the path.
  ///
  /// - Parameter distanceNM: Distance from the path origin, in nautical miles.
  /// - Returns: The closest point, or `nil` if the path has none.
  public func point(nearestToDistanceNM distanceNM: Double) -> Point? {
    points.min { abs($0.distanceNM - distanceNM) < abs($1.distanceNM - distanceNM) }
  }

  /// A single point along the terrain-enriched path.
  public struct Point: Sendable {
    /// Geographic coordinate of this path point.
    public let coordinate: CLLocationCoordinate2D
    /// Cumulative distance in nautical miles from the path origin.
    public let distanceNM: Double
    /// The path's ground track at this point, referenced to true north.
    ///
    /// What a wind is resolved against to say whether it helps or hinders the climb.
    public let track: Measurement<UnitAngle>
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

    /// The aircraft's altitude here, above mean sea level.
    public var altitudeMSL: Measurement<UnitLength> {
      .init(value: aircraftAltitudeFt, unit: .feet)
    }

    /// The aircraft's height above the terrain here, or `nil` where the region covering this point
    /// has not been downloaded.
    ///
    /// Nil rather than zero: nothing is known about the ground there, including whether the path
    /// clears it. Signed rather than clamped, so a path drawn through a ridge reads as being below
    /// it. Measured against the terrain alone — an obstacle standing on it is a separate mark on
    /// the chart, and folding one into a height above ground would misname it.
    ///
    /// Measured against the surveyed ground rather than the drawn one: where the ground falls away
    /// below the field, ``drawnTerrainElevationFt(fieldElevationFt:)`` floors the picture at the
    /// runway and this height does not, so the two deliberately disagree.
    public var altitudeAGL: Measurement<UnitLength>? {
      guard let terrainElevationFt else { return nil }
      return .init(value: aircraftAltitudeFt - terrainElevationFt, unit: .feet)
    }

    /// The elevation the terrain fill reaches here, in feet MSL.
    ///
    /// Ground below the field reads as being at the field, as does an undownloaded region: the
    /// profile is drawn from the runway upwards and has no room to say anything beneath it. This is
    /// the ground as drawn, not as surveyed — ``altitudeAGL`` answers the clearance question and
    /// measures against the surveyed elevation instead.
    ///
    /// - Parameter fieldElevationFt: The elevation of the airport, in feet MSL.
    /// - Returns: The elevation the terrain is drawn up to, in feet MSL.
    public func drawnTerrainElevationFt(fieldElevationFt: Double) -> Double {
      max(terrainElevationFt ?? fieldElevationFt, fieldElevationFt)
    }
  }
}
