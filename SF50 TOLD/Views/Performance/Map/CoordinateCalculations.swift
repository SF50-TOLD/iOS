import CoreLocation
import Foundation
import SF50_Shared

/// Earth's radius in meters for geodetic calculations.
private let earthRadius: Double = 6371000

/// Calculates the initial bearing from one coordinate to another.
///
/// Uses the forward azimuth formula to compute the bearing on a spherical Earth.
///
/// - Parameters:
///   - from: Starting coordinate.
///   - to: Destination coordinate.
/// - Returns: The initial bearing as a Measurement in degrees (0-360).
public func bearing(
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

/// Calculates a destination coordinate given a starting point, distance, and bearing.
///
/// Uses the Haversine formula to compute the destination on a spherical Earth.
///
/// - Parameters:
///   - from: Starting coordinate.
///   - distance: Distance to travel.
///   - bearing: True bearing in degrees (0-360).
/// - Returns: The destination coordinate.
public func destination(
  from start: CLLocationCoordinate2D,
  distance: Measurement<UnitLength>,
  bearing: Measurement<UnitAngle>
) -> CLLocationCoordinate2D {
  let distanceMeters = distance.converted(to: .meters).value
  let bearingRadians = bearing.converted(to: .radians).value

  let lat1 = start.latitude * .pi / 180
  let lon1 = start.longitude * .pi / 180

  let angularDistance = distanceMeters / earthRadius

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

/// Calculates the touchdown zone offset for landing calculations.
///
/// If threshold crossing height (TCH) and glidepath angle are available, calculates
/// the actual touchdown point using `distance = TCH / tan(angle)`. Otherwise falls back
/// to the lesser of 2000 feet or the middle of the first third of the runway.
///
/// - Parameters:
///   - runwayLength: Total runway length.
///   - thresholdCrossingHeight: TCH for approach (nil to use fallback).
///   - glidepathAngle: Glidepath angle from ILS or PAPI/VASI (nil to use fallback).
/// - Returns: Distance from threshold to touchdown zone.
public func touchdownZoneOffset(
  runwayLength: Measurement<UnitLength>,
  thresholdCrossingHeight: Measurement<UnitLength>? = nil,
  glidepathAngle: Measurement<UnitAngle>? = nil
) -> Measurement<UnitLength> {
  // If we have TCH and glidepath angle, calculate actual touchdown point
  // Formula: distance = TCH / tan(angle) (since gradient = rise/run = TCH/distance)
  if let thresholdCrossingHeight, let glidepathAngle,
    glidepathAngle.converted(to: .degrees).value > 0
  {
    let angleRadians = glidepathAngle.converted(to: .radians).value
    let gradient = tan(angleRadians)
    let tchMeters = thresholdCrossingHeight.converted(to: .meters).value
    return .init(value: tchMeters / gradient, unit: .meters)
  }

  // Fall back to current approximation
  let standardTouchdown = Measurement<UnitLength>(value: 2000, unit: .feet)
  let middleOfFirstThird = runwayLength / 6.0  // First third / 2 = 1/6

  if standardTouchdown < middleOfFirstThird {
    return standardTouchdown
  }
  return middleOfFirstThird
}

/// Calculates the four corner coordinates of a runway rectangle.
///
/// - Parameters:
///   - threshold: Threshold coordinate at the start of the runway.
///   - heading: True heading of the runway in degrees.
///   - length: Runway length.
///   - width: Runway width (defaults to 100 feet).
/// - Returns: Array of four coordinates representing the runway corners in clockwise order
///            starting from the left side of the threshold.
public func runwayCorners(
  threshold: CLLocationCoordinate2D,
  heading: Measurement<UnitAngle>,
  length: Measurement<UnitLength>,
  width: Measurement<UnitLength> = .init(value: 100, unit: .feet)
) -> [CLLocationCoordinate2D] {
  let halfWidth = width / 2.0
  let headingDegrees = heading.converted(to: .degrees).value

  // Calculate the perpendicular bearings (left and right of runway centerline)
  let leftBearing = Measurement<UnitAngle>(
    value: (headingDegrees - 90).truncatingRemainder(dividingBy: 360),
    unit: .degrees
  )
  let rightBearing = Measurement<UnitAngle>(
    value: (headingDegrees + 90).truncatingRemainder(dividingBy: 360),
    unit: .degrees
  )

  // Calculate the far end of the runway
  let farEnd = destination(from: threshold, distance: length, bearing: heading)

  // Calculate the four corners
  let thresholdLeft = destination(from: threshold, distance: halfWidth, bearing: leftBearing)
  let thresholdRight = destination(from: threshold, distance: halfWidth, bearing: rightBearing)
  let farEndLeft = destination(from: farEnd, distance: halfWidth, bearing: leftBearing)
  let farEndRight = destination(from: farEnd, distance: halfWidth, bearing: rightBearing)

  return [thresholdLeft, thresholdRight, farEndRight, farEndLeft]
}

/// Calculates the four corner coordinates for a ground run overlay on the runway.
///
/// - Parameters:
///   - startPoint: Starting coordinate of the ground run.
///   - heading: True heading of the runway in degrees.
///   - distance: Ground run distance.
///   - width: Runway width (defaults to 100 feet).
/// - Returns: Array of four coordinates representing the ground run rectangle in clockwise order.
public func groundRunCorners(
  startPoint: CLLocationCoordinate2D,
  heading: Measurement<UnitAngle>,
  distance: Measurement<UnitLength>,
  width: Measurement<UnitLength> = .init(value: 100, unit: .feet)
) -> [CLLocationCoordinate2D] {
  return runwayCorners(threshold: startPoint, heading: heading, length: distance, width: width)
}

/// A single chevron polygon with its coordinates and whether it uses primary or secondary opacity.
public struct ChevronData {
  /// The polygon coordinates for this chevron.
  public let coordinates: [CLLocationCoordinate2D]

  /// Whether this chevron uses primary (true) or secondary (false) opacity.
  public let isPrimary: Bool
}

/// Generates tessellated chevron polygons along a path to indicate direction of travel.
///
/// Each chevron is a filled V-shaped region pointing in the direction of travel.
/// Chevrons tessellate (connect without gaps) and alternate between primary and
/// secondary styling for visual effect.
///
/// - Parameters:
///   - startPoint: Starting coordinate of the path.
///   - heading: True heading in degrees.
///   - distance: Total distance to cover with chevrons.
///   - width: Width of the chevron band.
///   - depth: How far back each chevron extends (defaults to 60 feet). Also determines spacing.
/// - Returns: Array of ChevronData with coordinates and alternating primary/secondary flag.
public func generateChevrons(
  startPoint: CLLocationCoordinate2D,
  heading: Measurement<UnitAngle>,
  distance: Measurement<UnitLength>,
  width: Measurement<UnitLength>,
  depth: Measurement<UnitLength> = .init(value: 60, unit: .feet)
) -> [ChevronData] {
  var chevrons: [ChevronData] = []

  let headingDegrees = heading.converted(to: .degrees).value
  let leftBearing = Measurement<UnitAngle>(
    value: (headingDegrees - 90).truncatingRemainder(dividingBy: 360),
    unit: .degrees
  )
  let rightBearing = Measurement<UnitAngle>(
    value: (headingDegrees + 90).truncatingRemainder(dividingBy: 360),
    unit: .degrees
  )

  let halfWidth = width / 2.0
  let depthMeters = depth.converted(to: .meters).value
  let distanceMeters = distance.converted(to: .meters).value

  // Generate tessellated chevrons - alternating forward and backward pointing triangles
  // that fill the entire area with no gaps
  var currentDistance: Double = 0
  var isPrimary = true

  while currentDistance < distanceMeters {
    // Row position along the centerline
    let rowStart = destination(
      from: startPoint,
      distance: .init(value: currentDistance, unit: .meters),
      bearing: heading
    )
    let rowEnd = destination(
      from: startPoint,
      distance: .init(value: currentDistance + depthMeters, unit: .meters),
      bearing: heading
    )

    // Corner points
    let startLeft = destination(from: rowStart, distance: halfWidth, bearing: leftBearing)
    let startRight = destination(from: rowStart, distance: halfWidth, bearing: rightBearing)
    let endLeft = destination(from: rowEnd, distance: halfWidth, bearing: leftBearing)
    let endRight = destination(from: rowEnd, distance: halfWidth, bearing: rightBearing)

    // Forward-pointing chevron (tip at front center)
    // Triangle: tip -> back-right -> back-left
    let forwardChevron = [
      rowEnd,  // tip (front center)
      startRight,  // back right
      startLeft  // back left
    ]
    chevrons.append(ChevronData(coordinates: forwardChevron, isPrimary: isPrimary))

    // Backward-pointing chevrons on the sides (fill the gaps)
    // Left side triangle: tip at back-left, base at front
    let leftFill = [
      startLeft,  // tip (back left)
      endLeft,  // front left
      rowEnd  // front center
    ]
    chevrons.append(ChevronData(coordinates: leftFill, isPrimary: !isPrimary))

    // Right side triangle: tip at back-right, base at front
    let rightFill = [
      startRight,  // tip (back right)
      rowEnd,  // front center
      endRight  // front right
    ]
    chevrons.append(ChevronData(coordinates: rightFill, isPrimary: !isPrimary))

    currentDistance += depthMeters
    isPrimary.toggle()
  }

  return chevrons
}
