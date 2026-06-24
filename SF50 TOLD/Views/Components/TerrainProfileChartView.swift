import Accessibility
import Charts
import SF50_Shared
import SwiftUI

struct TerrainProfileChartView: View {
  let terrainPath: ProcedureTerrainPath
  let fieldElevationFt: Double

  var body: some View {
    Chart {
      terrainLayer
      obstacleLayer
      waypointLinesLayer
      climbPathLayer
      waypointLabelsLayer
    }
    .chartXAxisLabel("Distance (NM)")
    .chartYAxisLabel("Altitude MSL (ft)")
    .chartXScale(domain: 0...maxDistanceNM)
    .chartYScale(domain: fieldElevationFt...maxAltitudeFt)
    .chartXAxis {
      AxisMarks(values: .automatic(desiredCount: 6)) { value in
        AxisGridLine()
        AxisTick()
        AxisValueLabel {
          if let nm = value.as(Double.self) {
            Text(nm, format: .number.precision(.fractionLength(0...1)))
          }
        }
      }
    }
    .chartYAxis {
      AxisMarks(values: .automatic(desiredCount: 5)) { value in
        AxisGridLine()
        AxisTick()
        AxisValueLabel {
          if let ft = value.as(Double.self) {
            Text(ft, format: .number.precision(.fractionLength(0)))
          }
        }
      }
    }
    .accessibilityIdentifier("terrainProfileChart")
    .accessibilityChartDescriptor(
      TerrainProfileChartDescriptor(
        distancesNM: chartPoints.map(\.distanceNM),
        aircraftAltitudesFt: chartPoints.map(\.aircraftAltitudeFt),
        terrainAltitudesFt: filledTerrainFt,
        fieldElevationFt: fieldElevationFt,
        maxDistanceNM: maxDistanceNM,
        maxAltitudeFt: maxAltitudeFt
      )
    )
  }

  // MARK: - Layers

  @ChartContentBuilder private var terrainLayer: some ChartContent {
    let terrain = filledTerrainFt
    ForEach(Array(chartPoints.enumerated()), id: \.offset) { index, point in
      AreaMark(
        x: .value("Distance", point.distanceNM),
        yStart: .value("Base", fieldElevationFt),
        yEnd: .value("Terrain", terrain[index])
      )
      .foregroundStyle(Color.gray.opacity(0.4))
    }
    // Red impact overlay using RectangleMark — each rectangle is an
    // independent mark that won't get hidden by the gray AreaMark series.
    ForEach(Array(chartPoints.dropLast().enumerated()), id: \.offset) { index, _ in
      let nextIndex = index + 1
      let isImpact = interceptsTerrain(at: index) || interceptsTerrain(at: nextIndex)
      RectangleMark(
        xStart: .value("Start", chartPoints[index].distanceNM),
        xEnd: .value("End", chartPoints[nextIndex].distanceNM),
        yStart: .value("Base", fieldElevationFt),
        yEnd: .value(
          "ImpactTerrain",
          isImpact ? max(terrain[index], terrain[nextIndex]) : fieldElevationFt
        )
      )
      .foregroundStyle(Color.red.opacity(isImpact ? 0.6 : 0))
    }
  }

  @ChartContentBuilder private var obstacleLayer: some ChartContent {
    ForEach(Array(terrainPath.points.enumerated()), id: \.offset) { _, point in
      if let obstacleFt = point.maxObstacleHeightFt, obstacleFt > fieldElevationFt {
        let terrainFt = max(point.terrainElevationFt ?? fieldElevationFt, fieldElevationFt)
        let airborne =
          point.aircraftAltitudeFt > fieldElevationFt + ProcedurePathGenerator.screenHeightFt
        let violated = airborne && point.aircraftAltitudeFt <= obstacleFt
        if violated {
          RuleMark(
            x: .value("Distance", point.distanceNM),
            yStart: .value("Terrain", terrainFt),
            yEnd: .value("Obstacle", obstacleFt)
          )
          .lineStyle(StrokeStyle(lineWidth: 2.5))
          .foregroundStyle(.red)
        } else {
          RuleMark(
            x: .value("Distance", point.distanceNM),
            yStart: .value("Terrain", terrainFt),
            yEnd: .value("Obstacle", obstacleFt)
          )
          .lineStyle(StrokeStyle(lineWidth: 1.5))
          .foregroundStyle(.gray.opacity(0.5))
          RuleMark(
            x: .value("Distance", point.distanceNM),
            yStart: .value("Terrain", terrainFt),
            yEnd: .value("Obstacle", obstacleFt)
          )
          .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
          .foregroundStyle(.red.opacity(0.3))
        }
      }
    }
  }

  @ChartContentBuilder private var waypointLinesLayer: some ChartContent {
    ForEach(waypointPoints, id: \.distanceNM) { point in
      RuleMark(
        x: .value("Waypoint", point.distanceNM),
        yStart: .value("Base", fieldElevationFt),
        yEnd: .value("Top", maxAltitudeFt)
      )
      .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 4]))
      .foregroundStyle(.blue)
    }
  }

  @ChartContentBuilder private var waypointLabelsLayer: some ChartContent {
    ForEach(waypointPoints, id: \.distanceNM) { point in
      if let name = point.fixName {
        PointMark(
          x: .value("Waypoint", point.distanceNM),
          y: .value("Top", maxAltitudeFt)
        )
        .symbolSize(0)
        .annotation(position: .bottom, alignment: .center) {
          Text(name)
            .font(.caption2)
            .foregroundStyle(.blue)
            .padding(.horizontal, 2)
            .background(Color(.systemBackground))
        }
      }

      if let restriction = point.altitudeRestriction {
        restrictionMarks(
          for: restriction,
          at: point.distanceNM,
          aircraftAltitudeFt: point.aircraftAltitudeFt
        )
      }
    }
  }

  @ChartContentBuilder private var climbPathLayer: some ChartContent {
    ForEach(Array(chartPoints.enumerated()), id: \.offset) { _, point in
      LineMark(
        x: .value("Distance", point.distanceNM),
        y: .value("Aircraft", point.aircraftAltitudeFt)
      )
      .foregroundStyle(.purple)
      .lineStyle(StrokeStyle(lineWidth: 3))
    }
  }

  // MARK: - Helpers

  private var chartPoints: [ProcedureTerrainPath.Point] {
    terrainPath.points
  }

  private var filledTerrainFt: [Double] {
    chartPoints.map { max($0.terrainElevationFt ?? fieldElevationFt, fieldElevationFt) }
  }

  private var waypointPoints: [ProcedureTerrainPath.Point] {
    terrainPath.points.filter { $0.fixName != nil }
  }

  private var maxDistanceNM: Double {
    terrainPath.points.map(\.distanceNM).max() ?? 1
  }

  private var maxAltitudeFt: Double {
    let maxAircraft = terrainPath.points.map(\.aircraftAltitudeFt).max() ?? fieldElevationFt
    let maxTerrain = filledTerrainFt.max() ?? fieldElevationFt
    return max(maxAircraft, maxTerrain)
  }

  private func interceptsTerrain(at index: Int) -> Bool {
    let point = chartPoints[index]
    let terrainFt = filledTerrainFt[index]
    let airborne =
      point.aircraftAltitudeFt > fieldElevationFt + ProcedurePathGenerator.screenHeightFt
    return airborne && terrainFt > fieldElevationFt && point.aircraftAltitudeFt <= terrainFt
  }

  @ChartContentBuilder
  private func restrictionMarks(
    for restriction: AltitudeRestriction,
    at distanceNM: Double,
    aircraftAltitudeFt: Double
  ) -> some ChartContent {
    switch restriction {
      case .atOrAbove(let altitude):
        restrictionMark(
          at: distanceNM,
          altitudeFt: altitude.converted(to: .feet).value,
          triangle: .up,
          text: altitudeText(altitude),
          violated: aircraftAltitudeFt < altitude.converted(to: .feet).value
        )
      case .atOrBelow(let altitude):
        restrictionMark(
          at: distanceNM,
          altitudeFt: altitude.converted(to: .feet).value,
          triangle: .down,
          text: altitudeText(altitude),
          violated: aircraftAltitudeFt > altitude.converted(to: .feet).value
        )
      case .at(let altitude):
        restrictionMark(
          at: distanceNM,
          altitudeFt: altitude.converted(to: .feet).value,
          triangle: .upAndDown,
          text: altitudeText(altitude),
          violated: abs(aircraftAltitudeFt - altitude.converted(to: .feet).value) > 100
        )
      case .between(let minAlt, let maxAlt):
        restrictionMark(
          at: distanceNM,
          altitudeFt: maxAlt.converted(to: .feet).value,
          triangle: .down,
          text: altitudeText(maxAlt),
          violated: aircraftAltitudeFt > maxAlt.converted(to: .feet).value
        )
        restrictionMark(
          at: distanceNM,
          altitudeFt: minAlt.converted(to: .feet).value,
          triangle: .up,
          text: altitudeText(minAlt),
          violated: aircraftAltitudeFt < minAlt.converted(to: .feet).value
        )
    }
  }

  @ChartContentBuilder
  private func restrictionMark(
    at distanceNM: Double,
    altitudeFt: Double,
    triangle: TriangleDirection,
    text: String,
    violated: Bool
  ) -> some ChartContent {
    let triangleWidth: CGFloat = 10
    let triangleHeight: CGFloat = 8
    let halfHeight = triangleHeight / 2
    let color: Color = violated ? .red : .blue

    PointMark(
      x: .value("Fix", distanceNM),
      y: .value("Restriction", altitudeFt)
    )
    .symbolSize(0)
    .symbol {
      switch triangle {
        case .up:
          TriangleUp()
            .fill(color)
            .frame(width: triangleWidth, height: triangleHeight)
            .offset(y: -halfHeight)
        case .down:
          TriangleDown()
            .fill(color)
            .frame(width: triangleWidth, height: triangleHeight)
            .offset(y: halfHeight)
        case .upAndDown:
          VStack(spacing: 0) {
            TriangleUp()
              .fill(color)
              .frame(width: triangleWidth, height: triangleHeight)
            TriangleDown()
              .fill(color)
              .frame(width: triangleWidth, height: triangleHeight)
          }
      }
    }
    .annotation(position: .trailing) {
      Text(text)
        .font(.caption2)
        .foregroundStyle(color)
        .padding(.horizontal, 2)
        .background(Color(.systemBackground))
    }
  }

  private func altitudeText(_ altitude: Measurement<UnitLength>) -> String {
    let ft = altitude.converted(to: .feet).value
    return "\(Int(ft))'"
  }

  // MARK: - Subtypes

  private enum TriangleDirection {
    case up, down, upAndDown
  }

  private struct TriangleUp: Shape {
    func path(in rect: CGRect) -> Path {
      Path { p in
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
      }
    }
  }

  private struct TriangleDown: Shape {
    func path(in rect: CGRect) -> Path {
      Path { p in
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.closeSubpath()
      }
    }
  }

  /// Maps the terrain profile's two altitude-vs-distance series into an
  /// `AXChartDescriptor` so VoiceOver users can play an audio graph of the
  /// climb path and underlying terrain.
  private struct TerrainProfileChartDescriptor: AXChartDescriptorRepresentable {
    /// Minimum width applied to a degenerate (equal-bound) axis range so the
    /// audio graph spans a non-zero interval rather than collapsing to a point.
    private static let minimumAxisSpan = 1.0

    let distancesNM: [Double]
    let aircraftAltitudesFt: [Double]
    let terrainAltitudesFt: [Double]
    let fieldElevationFt: Double
    let maxDistanceNM: Double
    let maxAltitudeFt: Double

    private var distanceAxis: AXNumericDataAxisDescriptor {
      AXNumericDataAxisDescriptor(
        title: String(localized: "Distance (NM)"),
        range: nonDegenerateRange(lowerBound: 0, upperBound: maxDistanceNM),
        gridlinePositions: [],
        valueDescriptionProvider: { distanceNM in
          distanceNM.formatted(.number.precision(.fractionLength(0...1)))
        }
      )
    }

    private var altitudeAxis: AXNumericDataAxisDescriptor {
      AXNumericDataAxisDescriptor(
        title: String(localized: "Altitude MSL (ft)"),
        range: nonDegenerateRange(lowerBound: fieldElevationFt, upperBound: maxAltitudeFt),
        gridlinePositions: [],
        valueDescriptionProvider: { altitudeFt in
          Measurement(value: altitudeFt, unit: UnitLength.feet)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided))
        }
      )
    }

    private var climbPathSeries: AXDataSeriesDescriptor {
      AXDataSeriesDescriptor(
        name: String(localized: "Climb path"),
        isContinuous: true,
        dataPoints: zip(distancesNM, aircraftAltitudesFt).map { distanceNM, altitudeFt in
          AXDataPoint(x: distanceNM, y: altitudeFt)
        }
      )
    }

    private var terrainSeries: AXDataSeriesDescriptor {
      AXDataSeriesDescriptor(
        name: String(localized: "Terrain"),
        isContinuous: true,
        dataPoints: zip(distancesNM, terrainAltitudesFt).map { distanceNM, terrainFt in
          AXDataPoint(x: distanceNM, y: terrainFt)
        }
      )
    }

    func makeChartDescriptor() -> AXChartDescriptor {
      AXChartDescriptor(
        title: String(localized: "Terrain Profile"),
        summary: String(localized: "Aircraft climb path and terrain elevation versus distance."),
        xAxis: distanceAxis,
        yAxis: altitudeAxis,
        series: [climbPathSeries, terrainSeries]
      )
    }

    /// Returns a closed range widened to ``minimumAxisSpan`` when the bounds are
    /// equal, avoiding a zero-width audio-graph axis on degenerate paths.
    private func nonDegenerateRange(lowerBound: Double, upperBound: Double) -> ClosedRange<Double> {
      guard upperBound > lowerBound else {
        return lowerBound...(lowerBound + Self.minimumAxisSpan)
      }
      return lowerBound...upperBound
    }
  }
}
