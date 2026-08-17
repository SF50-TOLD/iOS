import CoreLocation
import Foundation

extension ProcedureTerrainPath {

  /// A sample climb from a sea-level field over rising terrain.
  ///
  /// Long enough to show a weather layer blending across it, and shallow enough that the terrain
  /// rises into the path near the end. Its track runs downwind of
  /// ``WindsAloftForecast/preview``'s westerlies, so a barb layer has a real component to draw
  /// rather than the near-pure crosswind a northerly track would give.
  public static var preview: Self {
    preview(
      lengthNM: 18,
      climbGradientFtPerNM: 320,
      track: .init(value: 105, unit: .degrees)
    )
  }

  private static func preview(
    lengthNM: Double,
    climbGradientFtPerNM: Double,
    track: Measurement<UnitAngle>
  ) -> Self {
    let origin = CLLocationCoordinate2D(latitude: 37.72, longitude: -122.22)
    let stepNM = 0.1

    let points = stride(from: 0, through: lengthNM, by: stepNM).map { distanceNM in
      Point(
        coordinate: GeoCalculations.destination(
          from: origin,
          distance: .init(value: distanceNM, unit: .nauticalMiles),
          bearing: track
        ),
        distanceNM: distanceNM,
        track: track,
        aircraftAltitudeFt: distanceNM * climbGradientFtPerNM,
        altitudeRestriction: nil,
        fixName: nil,
        terrainElevationFt: terrainFt(atDistanceNM: distanceNM, lengthNM: lengthNM),
        maxObstacleHeightFt: nil
      )
    }

    return .init(corridorWidthNM: 0.25, points: points)
  }

  /// Rolling terrain that climbs toward a ridge two thirds of the way along.
  private static func terrainFt(atDistanceNM distanceNM: Double, lengthNM: Double) -> Double {
    let ridge = 2200 * exp(-pow((distanceNM - lengthNM * 0.66) / (lengthNM * 0.14), 2))
    let rolling = 180 * sin(distanceNM * 1.4)
    return max(0, ridge + rolling)
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
