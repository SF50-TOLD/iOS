import MapKit
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

  @State private var cameraPosition: MapCameraPosition = .automatic

  private var runwayColor: Color {
    Color.gray.opacity(0.4)
  }

  /// Runway width, defaulting to 100 feet if not available.
  private var runwayWidth: Measurement<UnitLength> {
    runway.width ?? .init(value: 100, unit: .feet)
  }

  /// The starting point of the ground run, accounting for operation type and NOTAM offset.
  private var groundRunStartPoint: CLLocationCoordinate2D? {
    guard let threshold = runway.thresholdCoordinate else { return nil }

    var offset = notamOffset

    if operation == .landing {
      // Add touchdown zone offset for landing
      offset += touchdownZoneOffset(runwayLength: runway.length)
    }

    if offset.value > 0 {
      return destination(
        from: threshold,
        distance: offset,
        bearing: runway.trueHeading
      )
    }
    return threshold
  }

  /// The end point of the ground run.
  private var groundRunEndPoint: CLLocationCoordinate2D? {
    guard let startPoint = groundRunStartPoint else { return nil }
    return destination(
      from: startPoint,
      distance: groundRun,
      bearing: runway.trueHeading
    )
  }

  /// The four corners of the runway polygon.
  private var runwayPolygon: [CLLocationCoordinate2D]? {
    guard let threshold = runway.thresholdCoordinate else { return nil }
    return runwayCorners(
      threshold: threshold,
      heading: runway.trueHeading,
      length: runway.length,
      width: runwayWidth
    )
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
    let tdzOffset = touchdownZoneOffset(runwayLength: runway.length)
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
      // Runway outline
      if let polygon = runwayPolygon {
        MapPolygon(coordinates: polygon)
          .foregroundStyle(runwayColor)
          .stroke(Color.white, lineWidth: 2)
      }

      // Ground run with chevron pattern
      if let startPoint = groundRunStartPoint {
        ChevronOverlay(
          startPoint: startPoint,
          heading: runway.trueHeading,
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
    .toolbarBackground(.visible, for: .navigationBar)
    .onAppear {
      setupCamera()
    }
  }

  private func setupCamera() {
    guard let threshold = runway.thresholdCoordinate else { return }

    // Calculate the center of the runway
    let runwayEnd = destination(
      from: threshold,
      distance: runway.length,
      bearing: runway.trueHeading
    )

    let centerLat = (threshold.latitude + runwayEnd.latitude) / 2
    let centerLon = (threshold.longitude + runwayEnd.longitude) / 2
    let center = CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon)

    // Calculate appropriate distance based on runway length
    let runwayLengthMeters = runway.length.converted(to: .meters).value
    let distance = max(runwayLengthMeters * 1.5, 500)  // At least 500m, 1.5x runway length

    cameraPosition = .camera(
      MapCamera(
        centerCoordinate: center,
        distance: distance,
        heading: runway.trueHeading.converted(to: .degrees).value,
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
        notamOffset: .init(value: 0, unit: .feet)
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
        notamOffset: .init(value: 0, unit: .feet)
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
        notamOffset: .init(value: 0, unit: .feet)
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
        notamOffset: .init(value: 0, unit: .feet)
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
        notamOffset: .init(value: 0, unit: .feet)
      )
    }
  }
}

#Preview("With NOTAM Offset") {
  PreviewView(insert: .KOAK) { helper in
    let runway = try helper.load(airportID: "OAK", runway: "30")!

    return NavigationStack {
      RunwayMapView(
        runway: runway,
        groundRun: .init(value: 3000, unit: .feet),
        operation: .takeoff,
        notamOffset: .init(value: 500, unit: .feet)
      )
    }
  }
}
