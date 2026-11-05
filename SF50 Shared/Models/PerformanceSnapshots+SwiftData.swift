import Foundation
import MeasurementKit

extension NOTAMInput {
  /// Creates a snapshot from a SwiftData NOTAM model.
  /// - Parameter notam: The NOTAM to capture.
  public init(from notam: NOTAM) {
    self.init(
      contaminationType: notam.contamination?.type,
      contaminationDepth: .init(value: notam.contamination?.depth ?? 0, unit: .meters),
      rwyCC: notam.contamination?.rwyCC,
      takeoffDistanceShortening: notam.takeoffDistanceShortening,
      landingDistanceShortening: notam.landingDistanceShortening,
      obstacleHeight: notam.obstacleHeight,
      obstacleDistance: notam.obstacleDistance
    )
  }
}

extension RunwayInput {
  /// Creates a snapshot from SwiftData Runway and Airport models.
  /// - Parameters:
  ///   - runway: The runway to capture.
  ///   - airport: The airport the runway belongs to.
  ///   - notam: The NOTAM restricting that runway, or `nil` if none does.
  public init(from runway: Runway, airport: Airport, notam: NOTAM?) {
    self.init(
      id: runway.name,
      elevation: runway.elevationOrAirportElevation,
      trueHeading: runway.trueHeading,
      gradient: runway.gradientOrBestGuess,
      length: runway.length,
      takeoffRun: runway.takeoffRun,
      takeoffDistance: runway.takeoffDistance,
      landingDistance: runway.landingDistance,
      surfaceType: runway.surfaceType,
      recordedSurfaceType: runway.recordedSurfaceType,
      hasKnownGradient: runway.gradient != nil || runway.reciprocal != nil,
      notam: notam.map { NOTAMInput(from: $0) },
      airportVariation: airport.variation,
      thresholdCrossingHeight: runway.thresholdCrossingHeight,
      glidepathAngle: runway.glidepathAngle,
      displacedThresholdDistance: runway.displacedThresholdDistance
    )
  }
}

extension AirportInput {
  /// Creates a snapshot from a SwiftData Airport model.
  /// - Parameters:
  ///   - airport: The airport to capture.
  ///   - notams: The airport's NOTAMs, keyed by the runway designator each restricts, as
  ///     ``NOTAMStore/notams(at:)`` returns them.
  public init(from airport: Airport, notams: [String: NOTAM]) {
    self.init(
      recordID: airport.recordID,
      locationID: airport.locationID,
      name: airport.name,
      elevation: airport.elevation,
      variation: airport.variation,
      timeZone: airport.timeZone,
      runways: airport.runways.map {
        RunwayInput(from: $0, airport: airport, notam: notams[$0.name])
      }
    )
  }
}

extension RunwaySnapshot {
  /// Copies the facts a performance readout needs out of a SwiftData runway.
  ///
  /// SwiftData models are not `Sendable`, so a ``Runway`` cannot cross into a widget timeline
  /// entry or an App Intent result. The distances are the NOTAMed ones the app's own screens
  /// compare against, not the published lengths: a readout that measured against pavement a NOTAM
  /// has closed would call a runway usable that the app calls short.
  ///
  /// - Parameters:
  ///   - runway: The runway to snapshot.
  ///   - notam: The NOTAM restricting that runway, or `nil` if none does.
  public init(from runway: Runway, notam: NOTAM?) {
    self.init(
      name: runway.name,
      takeoffRun: runway.availableTakeoffRun(notamedBy: notam),
      takeoffDistance: runway.availableTakeoffDistance(notamedBy: notam),
      landingDistance: runway.availableLandingDistance(notamedBy: notam),
      trueHeading: runway.trueHeading
    )
  }
}
