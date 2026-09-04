public import CoreLocation
import Foundation
import MeasurementKit
import MeasurementKitLocation
import NavData

extension GeoCalculations {
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
  /// - Parameters:
  ///   - start: Starting coordinate.
  ///   - end: Destination coordinate.
  /// - Returns: The initial bearing as a Measurement in degrees (0-360).
  public static func bearing(
    from start: CLLocationCoordinate2D,
    to end: CLLocationCoordinate2D
  ) -> Measurement<UnitAngle> {
    start.geoCoordinate.initialBearing(to: end.geoCoordinate).angle.converted(to: .degrees)
  }

  /// Computes ground track and ground speed from the wind triangle.
  ///
  /// Stated in primitives rather than measurements because its only caller is the step engine,
  /// which integrates a path in degrees and knots: taking measurements here would have every step
  /// of the loop wrap its numbers and unwrap the answer.
  ///
  /// - Parameters:
  ///   - trueHeadingDeg: Aircraft true heading (direction nose points), in degrees.
  ///   - TAS_Kts: True airspeed in knots.
  ///   - windFromTrueDeg: Direction wind blows FROM (true north ref), in degrees.
  ///   - windSpeedKts: Wind speed in knots.
  /// - Returns: Ground track in degrees true (0–360) and ground speed in knots.
  public static func windTriangle(
    trueHeadingDeg: Double,
    TAS_Kts: Double,
    windFromTrueDeg: Double,
    windSpeedKts: Double
  ) -> (groundTrackDeg: Double, groundSpeedKts: Double) {
    let triangle = WindTriangle(
      heading: .init(degrees: trueHeadingDeg),
      trueAirspeed: .init(value: TAS_Kts, unit: .knots),
      windFrom: .init(degrees: windFromTrueDeg),
      windSpeed: .init(value: windSpeedKts, unit: .knots)
    )

    return (groundTrackDeg: triangle.track.degrees, groundSpeedKts: triangle.groundSpeed.value)
  }

  /// Calculates a destination coordinate given a starting point, distance, and bearing.
  ///
  /// - Parameters:
  ///   - start: Starting coordinate.
  ///   - distance: Distance to travel.
  ///   - bearing: True bearing in degrees (0-360).
  /// - Returns: The destination coordinate.
  public static func destination(
    from start: CLLocationCoordinate2D,
    distance: Measurement<UnitLength>,
    bearing: Measurement<UnitAngle>
  ) -> CLLocationCoordinate2D {
    start.geoCoordinate.offset(bearing: .init(bearing), distance: distance).clCoordinate
  }
}
