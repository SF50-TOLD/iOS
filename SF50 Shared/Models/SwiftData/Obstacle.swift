import CoreLocation
import Foundation
import SwiftData

/// An obstacle from the FAA Digital Obstacle File (DOF).
///
/// ``Obstacle`` represents a vertical obstruction that could affect aircraft
/// operations, such as towers, buildings, or terrain features. Obstacle data
/// is used for departure procedure planning and obstacle clearance calculations.
///
/// ## Topics
///
/// ### Location
/// - ``latitude``
/// - ``longitude``
/// - ``coordinate``
///
/// ### Height
/// - ``heightMSL``
@Model
public final class Obstacle {
  private var _heightMSL: Double  // meters
  private var _latitude: Double  // decimal degrees
  private var _longitude: Double  // decimal degrees

  /// Obstacle height above mean sea level
  public var heightMSL: Measurement<UnitLength> {
    get { .init(value: _heightMSL, unit: .meters) }
    set { _heightMSL = newValue.converted(to: .meters).value }
  }

  /// Obstacle latitude in degrees
  public var latitude: Measurement<UnitAngle> {
    get { .init(value: _latitude, unit: .degrees) }
    set { _latitude = newValue.converted(to: .degrees).value }
  }

  /// Obstacle longitude in degrees
  public var longitude: Measurement<UnitAngle> {
    get { .init(value: _longitude, unit: .degrees) }
    set { _longitude = newValue.converted(to: .degrees).value }
  }

  /// CoreLocation coordinate for the obstacle
  public var coordinate: CLLocationCoordinate2D {
    .init(
      latitude: latitude.converted(to: .degrees).value,
      longitude: longitude.converted(to: .degrees).value
    )
  }

  /// Creates a new obstacle.
  ///
  /// - Parameters:
  ///   - heightMSL: Height above mean sea level.
  ///   - latitude: Obstacle latitude.
  ///   - longitude: Obstacle longitude.
  public init(
    heightMSL: Measurement<UnitLength>,
    latitude: Measurement<UnitAngle>,
    longitude: Measurement<UnitAngle>
  ) {
    _heightMSL = heightMSL.converted(to: .meters).value
    _latitude = latitude.converted(to: .degrees).value
    _longitude = longitude.converted(to: .degrees).value
  }
}
