import CoreLocation
import MapKit
import SF50_Shared
import SwiftUI

/// A reusable MapContent that renders tessellated chevron patterns to indicate direction of travel.
///
/// The chevrons fill the entire area with alternating opacity levels to create a visual pattern.
/// Each chevron is a filled V-shape pointing in the direction of travel.
struct ChevronOverlay: MapContent {
  /// Starting coordinate of the chevron pattern.
  let startPoint: CLLocationCoordinate2D

  /// True heading in degrees.
  let heading: Measurement<UnitAngle>

  /// Total distance to cover with chevrons.
  let distance: Measurement<UnitLength>

  /// Width of the chevron band.
  let width: Measurement<UnitLength>

  /// Base color for the chevrons.
  let color: Color

  /// Primary opacity (for odd chevrons).
  var primaryOpacity: Double = 0.8

  /// Secondary opacity (for even chevrons).
  var secondaryOpacity: Double = 0.5

  /// How far back each chevron extends (also determines tessellation spacing).
  var depth: Measurement<UnitLength> = .init(value: 60, unit: .feet)

  var body: some MapContent {
    let chevrons = generateChevrons(
      startPoint: startPoint,
      heading: heading,
      distance: distance,
      width: width,
      depth: depth
    )

    ForEach(Array(chevrons.enumerated()), id: \.offset) { _, chevron in
      MapPolygon(coordinates: chevron.coordinates)
        .foregroundStyle(color.opacity(chevron.isPrimary ? primaryOpacity : secondaryOpacity))
    }
  }
}
