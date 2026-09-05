import CoreLocation
import Foundation

extension ProcedureTerrainPath {

  /// The named fixes the sample path passes, and what they hold the climb to.
  private static let previewFixes:
    [(distanceNM: Double, name: String, restriction: AltitudeRestriction?)] = [
      (4, "OAKEY", nil),
      (11, "LINDZ", .atOrAbove(.init(value: 3000, unit: .feet)))
    ]

  /// A sample climb from a sea-level field over rising terrain.
  ///
  /// Long enough to show a weather layer blending across it, and shallow enough that the terrain
  /// rises into the path near the end. Its track runs downwind of
  /// ``WindsAloftForecast/preview``'s westerlies, so a barb layer has a real component to draw
  /// rather than the near-pure crosswind a northerly track would give.
  ///
  /// Two of its points are named fixes, one of them carrying an altitude restriction, so a readout
  /// that only speaks at a fix has somewhere to speak.
  public static var preview: Self {
    preview(
      lengthNM: 18,
      climbGradientFtPerNM: 320,
      track: .init(value: 105, unit: .degrees)
    )
  }

  /// The same climb with no terrain downloaded under its middle third.
  ///
  /// What an undownloaded region looks like: not flat ground, and not zero clearance, but nothing
  /// known at all.
  public static var previewMissingTerrain: Self {
    preview(
      lengthNM: 18,
      climbGradientFtPerNM: 320,
      track: .init(value: 105, unit: .degrees),
      missingTerrainNM: 6..<9
    )
  }

  private static func preview(
    lengthNM: Double,
    climbGradientFtPerNM: Double,
    track: Measurement<UnitAngle>,
    missingTerrainNM: Range<Double>? = nil
  ) -> Self {
    let origin = CLLocationCoordinate2D(latitude: 37.72, longitude: -122.22)
    let stepNM = 0.1

    let points = stride(from: 0, through: lengthNM, by: stepNM).map { distanceNM in
      let fix = fix(atDistanceNM: distanceNM, stepNM: stepNM)
      return Point(
        coordinate: GeoCalculations.destination(
          from: origin,
          distance: .init(value: distanceNM, unit: .nauticalMiles),
          bearing: track
        ),
        distanceNM: distanceNM,
        track: track,
        aircraftAltitudeFt: distanceNM * climbGradientFtPerNM,
        altitudeRestriction: fix?.restriction,
        fixName: fix?.name,
        terrainElevationFt: missingTerrainNM?.contains(distanceNM) == true
          ? nil : terrainFt(atDistanceNM: distanceNM, lengthNM: lengthNM),
        maxObstacleHeightFt: nil
      )
    }

    return .init(corridorWidthNM: 0.25, points: points)
  }

  /// The fix standing at a distance, if the sample path names one within a step of it.
  private static func fix(atDistanceNM distanceNM: Double, stepNM: Double) -> (
    name: String, restriction: AltitudeRestriction?
  )? {
    previewFixes.first { abs($0.distanceNM - distanceNM) < stepNM / 2 }
      .map { ($0.name, $0.restriction) }
  }

  /// Rolling terrain that climbs toward a ridge two thirds of the way along.
  private static func terrainFt(atDistanceNM distanceNM: Double, lengthNM: Double) -> Double {
    let ridge = 2200 * exp(-pow((distanceNM - lengthNM * 0.66) / (lengthNM * 0.14), 2))
    let rolling = 180 * sin(distanceNM * 1.4)
    return max(0, ridge + rolling)
  }
}

extension ProcedureTerrainPath.Point {

  /// One sample, for a preview that wants a point rather than a whole path.
  public static func preview(
    distanceNM: Double = 11.9,
    aircraftAltitudeFt: Double = 3808,
    altitudeRestriction: AltitudeRestriction? = nil,
    fixName: String? = nil,
    terrainElevationFt: Double? = 2568,
    maxObstacleHeightFt: Double? = nil
  ) -> Self {
    .init(
      coordinate: .init(latitude: 37.72, longitude: -122.22),
      distanceNM: distanceNM,
      track: .init(value: 105, unit: .degrees),
      aircraftAltitudeFt: aircraftAltitudeFt,
      altitudeRestriction: altitudeRestriction,
      fixName: fixName,
      terrainElevationFt: terrainElevationFt,
      maxObstacleHeightFt: maxObstacleHeightFt
    )
  }
}

extension ClimbProfile {

  /// A sample climb profile flown on ``WindsAloftForecast/preview``'s winds.
  ///
  /// Its lowest reported level stands at 3,000 ft, as an FAA bulletin's does, so a preview shows the
  /// wind being carried down to the ground below it.
  public static var preview: Self {
    ClimbProfileGenerator.generate(
      windsAloft: ClimbProfileGenerator.windsAloftObservations(
        for: .preview,
        conditions: .init(temperature: .init(value: 6, unit: .celsius)),
        fieldElevation: .init(value: 0, unit: .feet)
      ),
      weightLb: 5500,
      aircraftType: .g2(updatedThrustSchedule: true),
      seaLevelPressureInHg: 29.92,
      useRegressionModel: true
    )
  }
}
