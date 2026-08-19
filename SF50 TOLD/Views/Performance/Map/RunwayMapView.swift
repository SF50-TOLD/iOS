import MapKit
import MeasurementKit
import SF50_Shared
import SwiftUI

/// Displays a satellite map visualization of calculated takeoff or landing distance on a runway.
///
/// The view shows:
/// - The runway outline as a semi-transparent gray polygon
/// - The calculated ground run distance as a colored overlay (blue for takeoff, green for landing)
/// - Markers at the start and end points of the ground run
struct RunwayMapView: View {
  /// The runway to display.
  let runway: Runway

  /// The calculated ground run distance.
  let groundRun: Measurement<UnitLength>

  /// Whether this is a takeoff or landing visualization.
  let operation: SF50_Shared.Operation

  /// Distance offset from threshold due to NOTAM restrictions.
  let notamOffset: Measurement<UnitLength>

  /// Location of the NOTAM shortening (threshold end or departure end).
  let shorteningLocation: ShorteningLocation

  @State private var cameraPosition: MapCameraPosition = .automatic

  private var runwayColor: Color { .gray.opacity(0.4) }

  /// Runway width, defaulting to 100 feet if not available.
  private var runwayWidth: Measurement<UnitLength> {
    runway.width ?? .init(value: 100, unit: .feet)
  }

  /// Runway heading calculated from threshold coordinates for precise alignment.
  ///
  /// When both runway ends have threshold coordinates, calculates the actual bearing
  /// between them for accurate polygon alignment with satellite imagery. Falls back
  /// to the NASR-provided heading (which is integer precision) if coordinates are unavailable.
  private var runwayHeading: Measurement<UnitAngle> {
    guard let startCoord = runway.takeoffStartCoordinate,
      let endCoord = runway.reciprocal?.thresholdCoordinate
    else { return runway.trueHeading }

    return bearing(from: startCoord, to: endCoord)
  }

  /// The starting point of the ground run, accounting for operation type and NOTAM offset.
  ///
  /// For takeoff, uses the physical runway start (displaced thresholds don't affect takeoff).
  /// For landing, uses the landing threshold plus touchdown zone offset.
  ///
  /// NOTAM offsets are only applied to the start point when the shortening is at the threshold end.
  /// For departure end shortening, the start point remains unchanged (but the runway is shorter).
  private var groundRunStartPoint: CLLocationCoordinate2D? {
    switch operation {
      case .takeoff:
        // Use physical runway start (takeoff can use displaced threshold area)
        guard let startPoint = runway.takeoffStartCoordinate else { return nil }

        // Only offset start if shortening is at threshold end
        if shorteningLocation == .thresholdEnd && notamOffset.value > 0 {
          return destination(
            from: startPoint,
            distance: notamOffset,
            bearing: runwayHeading
          )
        }
        return startPoint

      case .landing:
        // Use landing threshold plus touchdown zone offset
        guard let threshold = runway.thresholdCoordinate else { return nil }

        var offset = touchdownZoneOffset(
          runwayLength: runway.length,
          thresholdCrossingHeight: runway.thresholdCrossingHeight,
          glidepathAngle: runway.glidepathAngle
        )

        // Only add NOTAM offset if shortening is at threshold end
        if shorteningLocation == .thresholdEnd {
          offset = offset.adding(notamOffset)
        }

        if offset.value > 0 {
          return destination(
            from: threshold,
            distance: offset,
            bearing: runwayHeading
          )
        }
        return threshold
    }
  }

  /// The four corners of the usable runway polygon, accounting for NOTAM shortening.
  private var runwayPolygon: [CLLocationCoordinate2D]? {
    guard let physicalStart = runway.takeoffStartCoordinate else { return nil }

    let usableStart: CLLocationCoordinate2D
    var usableLength = runway.length

    switch (shorteningLocation, notamOffset.value > 0) {
      case (.thresholdEnd, true):
        // Threshold end shortened: start further down, reduce length
        usableStart = destination(
          from: physicalStart,
          distance: notamOffset,
          bearing: runwayHeading
        )
        usableLength = runway.length - notamOffset

      case (.departureEnd, true):
        // Departure end shortened: start at physical start, reduce length
        usableStart = physicalStart
        usableLength = runway.length - notamOffset

      case (_, false):
        // No shortening
        usableStart = physicalStart
    }

    return runwayCorners(
      threshold: usableStart,
      heading: runwayHeading,
      length: usableLength,
      width: runwayWidth
    )
  }

  /// The four corners of the closed/unusable portion of the runway due to NOTAM shortening.
  private var closedRunwayPolygon: [CLLocationCoordinate2D]? {
    guard notamOffset.value > 0,
      let physicalStart = runway.takeoffStartCoordinate
    else { return nil }

    switch shorteningLocation {
      case .thresholdEnd:
        // Closed portion is at the start of the runway
        return runwayCorners(
          threshold: physicalStart,
          heading: runwayHeading,
          length: notamOffset,
          width: runwayWidth
        )

      case .departureEnd:
        // Closed portion is at the end of the runway
        let closedStart = destination(
          from: physicalStart,
          distance: runway.length - notamOffset,
          bearing: runwayHeading
        )
        return runwayCorners(
          threshold: closedStart,
          heading: runwayHeading,
          length: notamOffset,
          width: runwayWidth
        )
    }
  }

  /// The status level for the current ground run.
  private var groundRunStatus: GroundRunStatus {
    if operation == .takeoff {
      let availableDistance = runway.takeoffDistanceOrLength - notamOffset
      if groundRun > availableDistance {
        return .danger
      }
      return .safe
    }

    // Landing
    let availableDistance = runway.landingDistanceOrLength - notamOffset
    let tdzOffset = touchdownZoneOffset(
      runwayLength: runway.length,
      thresholdCrossingHeight: runway.thresholdCrossingHeight,
      glidepathAngle: runway.glidepathAngle
    )
    let availableFromTouchdown = availableDistance - tdzOffset

    if groundRun > availableDistance {
      return .danger
    }
    if groundRun > availableFromTouchdown {
      return .warning
    }
    return .safe
  }

  var body: some View {
    Map(position: $cameraPosition) {
      // Closed/unusable runway portion (shown in red)
      if let closedPolygon = closedRunwayPolygon {
        MapPolygon(coordinates: closedPolygon)
          .foregroundStyle(Color.red.opacity(0.3))
          .stroke(Color.red.opacity(0.6), lineWidth: 2)
      }

      // Usable runway outline
      if let polygon = runwayPolygon {
        MapPolygon(coordinates: polygon)
          .foregroundStyle(runwayColor)
          .stroke(Color.white, lineWidth: 2)
      }

      // Ground run with chevron pattern
      if let startPoint = groundRunStartPoint {
        ChevronOverlay(
          startPoint: startPoint,
          heading: runwayHeading,
          distance: groundRun,
          width: runwayWidth,
          color: groundRunStatus.color,
          primaryOpacity: groundRunStatus.primaryOpacity,
          secondaryOpacity: groundRunStatus.secondaryOpacity
        )
      }
    }
    .mapStyle(.imagery(elevation: .realistic))
    .navigationTitle("Runway \(runway.name)")
    .navigationBarTitleDisplayMode(.inline)
    .onAppear {
      setupCamera()
    }
  }

  private func setupCamera() {
    guard let runwayStart = runway.takeoffStartCoordinate else { return }

    // Calculate the center of the runway using the physical start
    let runwayEnd = destination(
      from: runwayStart,
      distance: runway.length,
      bearing: runwayHeading
    )

    let centerLat = (runwayStart.latitude + runwayEnd.latitude) / 2
    let centerLon = (runwayStart.longitude + runwayEnd.longitude) / 2
    let center = CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon)

    // Calculate appropriate distance based on runway length
    let runwayLengthMeters = runway.length.converted(to: .meters).value
    let distance = max(runwayLengthMeters * 1.5, 500)  // At least 500m, 1.5x runway length

    cameraPosition = .camera(
      MapCamera(
        centerCoordinate: center,
        distance: distance,
        heading: runwayHeading.converted(to: .degrees).value,
        pitch: 45
      )
    )
  }

  /// Status level for the ground run visualization.
  private enum GroundRunStatus {
    case safe  // Blue - within limits
    case warning  // Yellow - marginal
    case danger  // Red - exceeds limits

    var color: Color {
      switch self {
        case .safe: return .blue
        case .warning: return .yellow
        case .danger: return .red
      }
    }

    /// Primary opacity tuned for each color's perceptual contrast.
    var primaryOpacity: Double {
      switch self {
        case .safe: return 0.9  // Blue needs more contrast
        case .warning: return 0.8  // Yellow is naturally high contrast
        case .danger: return 0.85  // Red needs moderate contrast
      }
    }

    /// Secondary opacity tuned for each color's perceptual contrast.
    var secondaryOpacity: Double {
      switch self {
        case .safe: return 0.4  // Blue needs more contrast
        case .warning: return 0.5  // Yellow is naturally high contrast
        case .danger: return 0.45  // Red needs moderate contrast
      }
    }
  }
}

#Preview("Takeoff - Blue") {
  PreviewView(insert: .KOAK) { helper in
    // OAK runway 28R is 5457 ft
    // Ground run 2500 ft <= 5457 ft → blue (within available distance)
    let runway = try helper.load(airportID: "OAK", runway: "28R")!

    return NavigationStack {
      RunwayMapView(
        runway: runway,
        groundRun: .init(value: 2500, unit: .feet),
        operation: .takeoff,
        notamOffset: .init(value: 0, unit: .feet),
        shorteningLocation: .departureEnd
      )
    }
  }
}

#Preview("Takeoff - Red") {
  PreviewView(insert: .KOAK) { helper in
    // OAK runway 28R is 5457 ft
    // Ground run 6000 ft > 5457 ft → red (exceeds available distance)
    let runway = try helper.load(airportID: "OAK", runway: "28R")!

    return NavigationStack {
      RunwayMapView(
        runway: runway,
        groundRun: .init(value: 6000, unit: .feet),
        operation: .takeoff,
        notamOffset: .init(value: 0, unit: .feet),
        shorteningLocation: .departureEnd
      )
    }
  }
}

#Preview("Landing - Blue") {
  PreviewView(insert: .KSQL) { helper in
    // SQL runway 30 is 2621 ft, TDZ ~437 ft, so available from TDZ ~2184 ft
    // Ground run 1500 ft <= 2184 ft → blue (can stop after normal touchdown)
    let runway = try helper.load(airportID: "SQL", runway: "30")!

    return NavigationStack {
      RunwayMapView(
        runway: runway,
        groundRun: .init(value: 1500, unit: .feet),
        operation: .landing,
        notamOffset: .init(value: 0, unit: .feet),
        shorteningLocation: .departureEnd
      )
    }
  }
}

#Preview("Landing - Yellow") {
  PreviewView(insert: .KSQL) { helper in
    // SQL runway 30 is 2621 ft, TDZ ~437 ft, so available from TDZ ~2184 ft
    // Ground run 2300 ft > 2184 ft but <= 2621 ft → yellow (must touch down early)
    let runway = try helper.load(airportID: "SQL", runway: "30")!

    return NavigationStack {
      RunwayMapView(
        runway: runway,
        groundRun: .init(value: 2300, unit: .feet),
        operation: .landing,
        notamOffset: .init(value: 0, unit: .feet),
        shorteningLocation: .departureEnd
      )
    }
  }
}

#Preview("Landing - Red") {
  PreviewView(insert: .KSQL) { helper in
    // SQL runway 30 is 2621 ft
    // Ground run 2800 ft > 2621 ft → red (impossible to stop)
    let runway = try helper.load(airportID: "SQL", runway: "30")!

    return NavigationStack {
      RunwayMapView(
        runway: runway,
        groundRun: .init(value: 2800, unit: .feet),
        operation: .landing,
        notamOffset: .init(value: 0, unit: .feet),
        shorteningLocation: .departureEnd
      )
    }
  }
}

#Preview("NOTAM - DER Shortening") {
  PreviewView(insert: .KOAK) { helper in
    let runway = try helper.load(airportID: "OAK", runway: "30")!

    return NavigationStack {
      RunwayMapView(
        runway: runway,
        groundRun: .init(value: 3000, unit: .feet),
        operation: .takeoff,
        notamOffset: .init(value: 500, unit: .feet),
        shorteningLocation: .departureEnd
      )
    }
  }
}

#Preview("NOTAM - Threshold Shortening") {
  PreviewView(insert: .KOAK) { helper in
    let runway = try helper.load(airportID: "OAK", runway: "30")!

    return NavigationStack {
      RunwayMapView(
        runway: runway,
        groundRun: .init(value: 3000, unit: .feet),
        operation: .takeoff,
        notamOffset: .init(value: 500, unit: .feet),
        shorteningLocation: .thresholdEnd
      )
    }
  }
}
