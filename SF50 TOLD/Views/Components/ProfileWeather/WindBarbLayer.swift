import Charts
import MeasurementKit
import SF50_Shared
import SwiftUI

/// The along-track wind, drawn as barbs on a grid across a climb profile's visible band.
///
/// Marks rather than a drawn field, unlike ``WeatherFieldLayer``: a barb stands at one distance and
/// one altitude, so it belongs to the chart's own scales rather than to a canvas that would have to
/// place it by hand.
///
/// The wind is read from `ClimbProfile`, which carries its lowest reported level down to the
/// ground rather than fading to calm — a clamped real wind describes the air better than an invented
/// still one. Barbs standing below that lowest level are drawn muted, so what is reported is told
/// apart from what is carried down.
struct WindBarbLayer: ChartContent {

  // MARK: - Constants

  /// How many rows of barbs the visible altitude band is divided into.
  private static let rows = 5

  /// How many columns of barbs the visible distance is divided into.
  private static let columns = 5

  // MARK: - Inputs

  /// The path being plotted, for the track a wind is resolved against and the terrain it hides
  /// behind.
  let terrainPath: ProcedureTerrainPath

  /// The climb profile the path was flown on, which the barbs are read from.
  let climbProfile: ClimbProfile

  /// The elevation of the departure or arrival airport.
  let fieldElevation: Measurement<UnitLength>

  /// The far end of the plotted distance, in nautical miles.
  let maxDistanceNM: Double

  /// The top of the plotted altitude band.
  let maxAltitude: Measurement<UnitLength>

  // The barbs are placed on the chart's own scales, so the band is read in feet once here and the
  // grid is laid out in those.
  private var fieldElevationFt: Double { fieldElevation.converted(to: .feet).value }

  private var maxAltitudeFt: Double { maxAltitude.converted(to: .feet).value }

  var body: some ChartContent {
    ForEach(positions, id: \.self) { position in
      PointMark(
        x: .value("Distance", position.distanceNM),
        y: .value("Altitude", position.altitudeFt)
      )
      .symbolSize(0)
      .foregroundStyle(.primary)
      .symbol {
        WindBarb(component: position.component, isExtrapolated: position.isExtrapolated)
      }
    }
  }

  /// The lowest altitude the winds aloft forecast actually reports at, in feet MSL.
  private var lowestReportedFt: Double? {
    climbProfile.dataPoints.first?.altitudeFt
  }

  /// The altitudes barbs are taken at, spread evenly across the visible band.
  private var altitudeGrid: [Double] {
    let span = maxAltitudeFt - fieldElevationFt
    guard span > 0 else { return [fieldElevationFt] }
    let step = span / Double(Self.rows + 1)
    return (1...Self.rows).map { fieldElevationFt + step * Double($0) }
  }

  /// Where each barb stands and what it says.
  ///
  /// Barbs buried in terrain are dropped rather than left for the terrain fill to cover, so the
  /// chart carries no mark that can't be seen.
  private var positions: [Position] {
    guard maxDistanceNM > 0 else { return [] }
    let columnStep = maxDistanceNM / Double(Self.columns + 1)

    return altitudeGrid.flatMap { altitudeFt -> [Position] in
      guard let directionDeg = climbProfile.windDirection(at: altitudeFt),
        let speedKts = climbProfile.windSpeed(at: altitudeFt)
      else { return [] }

      return (1...Self.columns).compactMap { column in
        let distanceNM = columnStep * Double(column)
        guard altitudeFt > terrainFt(atDistanceNM: distanceNM) else { return nil }

        return .init(
          distanceNM: distanceNM,
          altitudeFt: altitudeFt,
          component: alongTrackComponent(
            windDirection: .init(value: directionDeg, unit: .degrees),
            windSpeed: .init(value: speedKts, unit: .knots),
            atDistanceNM: distanceNM
          ),
          isExtrapolated: altitudeFt < (lowestReportedFt ?? -.infinity)
        )
      }
    }
  }

  // MARK: - Sampling

  /// The wind resolved onto the path's track: positive downwind of the aircraft, negative against.
  ///
  /// Wind direction is the direction the wind blows *from*, so a wind on the nose — blowing from
  /// straight ahead — gives a cosine of one and is reported as a headwind.
  private func alongTrackComponent(
    windDirection: Measurement<UnitAngle>,
    windSpeed: Measurement<UnitSpeed>,
    atDistanceNM distanceNM: Double
  ) -> Measurement<UnitSpeed> {
    -windSpeed * cos(windDirection - track(atDistanceNM: distanceNM))
  }

  private func track(atDistanceNM distanceNM: Double) -> Measurement<UnitAngle> {
    nearestPoint(toDistanceNM: distanceNM)?.track ?? .init(value: 0, unit: .degrees)
  }

  private func terrainFt(atDistanceNM distanceNM: Double) -> Double {
    guard let point = nearestPoint(toDistanceNM: distanceNM) else { return fieldElevationFt }
    return max(point.terrainElevationFt ?? fieldElevationFt, fieldElevationFt)
  }

  private func nearestPoint(toDistanceNM distanceNM: Double) -> ProcedureTerrainPath.Point? {
    terrainPath.points.min { abs($0.distanceNM - distanceNM) < abs($1.distanceNM - distanceNM) }
  }

  // MARK: - Subtypes

  /// One barb: where it stands, what it reads, and whether it was carried down to get there.
  private struct Position: Hashable {
    let distanceNM: Double
    let altitudeFt: Double
    let component: Measurement<UnitSpeed>
    let isExtrapolated: Bool
  }
}
