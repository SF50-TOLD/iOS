import Accessibility
import Charts
import SF50_Shared
import SwiftUI

struct TerrainProfileChartView: View {

  // MARK: - Constants

  /// How much of the terrain fill's colour is gray, the rest being the ground it stands on.
  private static let terrainGrayFraction = 0.4

  /// The colour terrain is filled with.
  ///
  /// Opaque, and mixed against the chart's own background rather than laid over it at a fraction:
  /// a weather field is drawn into that background, and a translucent fill would let cloud and
  /// icing show through solid ground.
  private static let terrainTint = Color(.systemBackground)
    .mix(with: .gray, by: terrainGrayFraction)

  /// How far from an "at" restriction the aircraft may stand before the mark reads as violated.
  private static let atRestrictionTolerance = Measurement(value: 100, unit: UnitLength.feet)

  /// Screen height in the feet the chart plots in.
  private static let screenHeightFt = ProcedurePathGenerator.screenHeight
    .converted(to: .feet).value

  // MARK: - Inputs

  let terrainPath: ProcedureTerrainPath

  /// The elevation of the departure or arrival airport, which the chart is drawn up from.
  let fieldElevation: Measurement<UnitLength>

  /// The atmosphere along the path, for whichever weather field is showing.
  var atmosphere: PathAtmosphere?

  /// The climb profile the path was flown on, which the wind barbs are read from.
  ///
  /// Reading the barbs from the profile rather than from the forecast behind it is what keeps them
  /// agreeing with the plotted path, including where the profile carries its lowest reported wind
  /// down to the ground.
  var climbProfile: ClimbProfile?

  /// The weather field drawn behind the terrain and the path.
  var weatherLayer: WeatherProfileLayer = .none

  /// Whether the along-track wind barbs are drawn.
  var showsWindBarbs = false

  var body: some View {
    Chart {
      // The weather reads behind the ground it describes, so both layers drawn from it are
      // declared before the terrain that covers them.
      freezingLevelLayer
      if showsWindBarbs, let climbProfile {
        WindBarbLayer(
          terrainPath: terrainPath,
          climbProfile: climbProfile,
          fieldElevation: fieldElevation,
          maxDistanceNM: maxDistanceNM,
          maxAltitude: maxAltitude
        )
      }
      terrainLayer
      obstacleLayer
      waypointLinesLayer
      climbPathLayer
      waypointLabelsLayer
    }
    .chartBackground { proxy in
      if let atmosphere {
        WeatherFieldLayer(proxy: proxy, atmosphere: atmosphere, layer: weatherLayer)
      }
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
      .foregroundStyle(Self.terrainTint)
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
          point.aircraftAltitudeFt > fieldElevationFt + Self.screenHeightFt
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
          aircraftAltitude: .init(value: point.aircraftAltitudeFt, unit: .feet)
        )
      }
    }
  }

  /// Where the temperature crosses freezing, drawn on the temperature and icing fields.
  @ChartContentBuilder private var freezingLevelLayer: some ChartContent {
    if weatherLayer == .temperature || weatherLayer == .icing {
      ForEach(freezingLevelPoints) { point in
        LineMark(
          x: .value("Distance", point.distanceNM),
          y: .value("Freezing level", point.altitudeFt),
          series: .value("Series", "freezing")
        )
        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [6, 3]))
        .foregroundStyle(.blue)
      }

      if let freezing = freezingLevelPoints.last {
        PointMark(
          x: .value("Distance", freezing.distanceNM),
          y: .value("Freezing level", freezing.altitudeFt)
        )
        .symbolSize(0)
        .annotation(position: .topTrailing, alignment: .trailing, spacing: 2) {
          Text("0 °C")
            .font(.caption2)
            .foregroundStyle(.blue)
            .padding(.horizontal, 2)
            .background(Color(.systemBackground))
        }
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

  private var maxAltitude: Measurement<UnitLength> {
    terrainPath.maxAltitude(fieldElevation: fieldElevation)
  }

  // The chart's own scales are plain numbers, so both bounds are read in feet once here and the
  // marks are plotted from these.
  private var fieldElevationFt: Double { fieldElevation.converted(to: .feet).value }

  private var maxAltitudeFt: Double { maxAltitude.converted(to: .feet).value }

  private var freezingLevelPoints: [FreezingLevelPoint] {
    guard let atmosphere else { return [] }
    return atmosphere.freezingLevel(
      toDistanceNM: maxDistanceNM,
      between: fieldElevation,
      and: maxAltitude
    )
    .map { .init(distanceNM: $0.distanceNM, altitudeFt: $0.altitude.converted(to: .feet).value) }
  }

  private func interceptsTerrain(at index: Int) -> Bool {
    let point = chartPoints[index]
    let terrainFt = filledTerrainFt[index]
    let airborne = point.aircraftAltitudeFt > fieldElevationFt + Self.screenHeightFt
    return airborne && terrainFt > fieldElevationFt && point.aircraftAltitudeFt <= terrainFt
  }

  @ChartContentBuilder
  private func restrictionMarks(
    for restriction: AltitudeRestriction,
    at distanceNM: Double,
    aircraftAltitude: Measurement<UnitLength>
  ) -> some ChartContent {
    switch restriction {
      case .atOrAbove(let altitude):
        restrictionMark(
          at: distanceNM,
          altitude: altitude,
          triangle: .up,
          violated: aircraftAltitude < altitude
        )
      case .atOrBelow(let altitude):
        restrictionMark(
          at: distanceNM,
          altitude: altitude,
          triangle: .down,
          violated: aircraftAltitude > altitude
        )
      case .at(let altitude):
        restrictionMark(
          at: distanceNM,
          altitude: altitude,
          triangle: .upAndDown,
          violated: (aircraftAltitude - altitude).magnitude > Self.atRestrictionTolerance
        )
      case .between(let minAlt, let maxAlt):
        restrictionMark(
          at: distanceNM,
          altitude: maxAlt,
          triangle: .down,
          violated: aircraftAltitude > maxAlt
        )
        restrictionMark(
          at: distanceNM,
          altitude: minAlt,
          triangle: .up,
          violated: aircraftAltitude < minAlt
        )
    }
  }

  @ChartContentBuilder
  private func restrictionMark(
    at distanceNM: Double,
    altitude: Measurement<UnitLength>,
    triangle: TriangleDirection,
    violated: Bool
  ) -> some ChartContent {
    let altitudeFt = altitude.converted(to: .feet).value
    let text = altitudeText(altitude)
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

  /// One sample of the freezing level.
  private struct FreezingLevelPoint: Identifiable {
    let distanceNM: Double
    let altitudeFt: Double

    var id: Double { distanceNM }
  }

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

// periphery:ignore - consumed only by the #Preview macros below
private struct ChartPreview: View {
  let layer: WeatherProfileLayer
  var showsWindBarbs = false
  var atmosphere: PathAtmosphere? = .previewMultiColumn

  var body: some View {
    TerrainProfileChartView(
      terrainPath: .preview,
      fieldElevation: .zero,
      atmosphere: atmosphere,
      climbProfile: .preview,
      weatherLayer: layer,
      showsWindBarbs: showsWindBarbs
    )
    .frame(height: 300)
    .padding()
  }
}

#Preview("No weather") {
  ChartPreview(layer: .none)
}

#Preview("Temperature") {
  ChartPreview(layer: .temperature)
}

#Preview("Clouds") {
  ChartPreview(layer: .clouds)
}

#Preview("Icing") {
  ChartPreview(layer: .icing)
}

/// Barbs over a field, the two layers the picker and the toggle can show at once. Drawn from the
/// single column a departure inside one forecast's reach actually gets.
#Preview("Wind barbs over temperature") {
  ChartPreview(layer: .temperature, showsWindBarbs: true, atmosphere: .preview)
}

/// Barbs alone, where the wind below 3,000 ft is carried down from the lowest reported level and
/// drawn muted to say so.
#Preview("Wind barbs only") {
  ChartPreview(layer: .none, showsWindBarbs: true, atmosphere: nil)
}
