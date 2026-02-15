import CoreLocation
import Foundation

/// A geographic flight path generated from a procedure's fix sequence.
public struct ProcedurePath: Sendable {
  public let points: [Point]

  public var coordinates: [CLLocationCoordinate2D] { points.map(\.coordinate) }

  public var totalDistanceNM: Double { points.last?.distanceNM ?? 0 }

  init(points: [Point]) {
    self.points = points
  }

  public struct Point: Sendable {
    /// Geographic coordinate of this path point.
    public let coordinate: CLLocationCoordinate2D
    /// Cumulative distance in nautical miles from the path origin.
    public let distanceNM: Double
    /// Computed aircraft altitude in feet at this point.
    public let altitudeFt: Double
    /// Elapsed time in seconds from the path origin.
    public let elapsedTimeSeconds: Double
    /// Altitude restriction at this point, if any.
    public let altitudeRestriction: AltitudeRestriction?
    /// Fix/waypoint name at this point, if any.
    public let fixName: String?

    init(
      coordinate: CLLocationCoordinate2D,
      distanceNM: Double,
      altitudeFt: Double,
      elapsedTimeSeconds: Double = 0,
      altitudeRestriction: AltitudeRestriction? = nil,
      fixName: String? = nil
    ) {
      self.coordinate = coordinate
      self.distanceNM = distanceNM
      self.altitudeFt = altitudeFt
      self.elapsedTimeSeconds = elapsedTimeSeconds
      self.altitudeRestriction = altitudeRestriction
      self.fixName = fixName
    }
  }
}
