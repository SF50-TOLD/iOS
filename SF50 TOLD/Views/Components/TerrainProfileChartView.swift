import Accessibility
import Charts
import Defaults
import MeasurementKit
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

  /// Screen height in the feet the chart reasons in.
  private static let screenHeightFt = ProcedurePathGenerator.screenHeight
    .converted(to: .feet).value

  /// How solid the rule marking the scrubbed sample is drawn.
  ///
  /// Drawn in gray rather than a tint: blue is already the fix lines and their restriction marks,
  /// red the violations, and purple the path.
  private static let selectionRuleOpacity = 0.7

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

  @Default(.heightUnit)
  private var heightUnit

  @Default(.distanceUnit)
  private var distanceUnit

  /// Where along the distance axis the pilot is scrubbing, in the axis's own unit.
  ///
  /// Held as the gesture reports it rather than snapped to a sample: writing a snapped value back
  /// would fight the drag it came from. ``selectedPoint`` does the snapping on the way out.
  ///
  /// Being in the axis's unit, it means nothing once that unit changes, and is dropped when it does.
  @State private var selectedDistance: Double?

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
          maxAltitude: maxAltitude,
          scale: scale
        )
      }
      terrainLayer
      obstacleLayer
      waypointLinesLayer
      climbPathLayer
      waypointLabelsLayer
      selectionLayer
    }
    .chartBackground { proxy in
      if let atmosphere {
        WeatherFieldLayer(
          proxy: proxy,
          atmosphere: atmosphere,
          layer: weatherLayer,
          scale: scale
        )
      }
    }
    .chartXAxisLabel("Distance (\(distanceUnit.symbol))")
    .chartYAxisLabel("Altitude MSL (\(heightUnit.symbol))")
    .chartXScale(domain: 0...axisMaxDistance)
    .chartYScale(domain: axisFieldElevation...axisMaxAltitude)
    .chartXAxis {
      AxisMarks(values: .automatic(desiredCount: 6)) { value in
        AxisGridLine()
        AxisTick()
        AxisValueLabel {
          if let distance = value.as(Double.self) {
            Text(distance, format: .number.precision(.fractionLength(0...1)))
          }
        }
      }
    }
    .chartYAxis {
      AxisMarks(values: .automatic(desiredCount: 5)) { value in
        AxisGridLine()
        AxisTick()
        AxisValueLabel {
          if let altitude = value.as(Double.self) {
            Text(altitude, format: .number.precision(.fractionLength(0)))
          }
        }
      }
    }
    .chartXSelection(value: $selectedDistance)
    .onChange(of: scale) { selectedDistance = nil }
    .accessibilityIdentifier("terrainProfileChart")
    .accessibilityChartDescriptor(
      TerrainProfileChartDescriptor(
        distances: chartPoints.map { scale.axisDistance(nm: $0.distanceNM) },
        aircraftAltitudes: chartPoints.map { scale.axisAltitude(ft: $0.aircraftAltitudeFt) },
        terrainAltitudes: filledTerrainFt.map { scale.axisAltitude(ft: $0) },
        fieldElevation: axisFieldElevation,
        maxDistance: axisMaxDistance,
        maxAltitude: axisMaxAltitude,
        scale: scale
      )
    )
  }

  // MARK: - Layers

  @ChartContentBuilder private var terrainLayer: some ChartContent {
    let terrain = filledTerrainFt
    ForEach(Array(chartPoints.enumerated()), id: \.offset) { index, point in
      AreaMark(
        x: .value("Distance", scale.axisDistance(nm: point.distanceNM)),
        yStart: .value("Base", axisFieldElevation),
        yEnd: .value("Terrain", scale.axisAltitude(ft: terrain[index]))
      )
      .foregroundStyle(Self.terrainTint)
    }
    // Red impact overlay using RectangleMark — each rectangle is an
    // independent mark that won't get hidden by the gray AreaMark series.
    ForEach(Array(chartPoints.dropLast().enumerated()), id: \.offset) { index, _ in
      let nextIndex = index + 1
      let isImpact = interceptsTerrain(at: index) || interceptsTerrain(at: nextIndex)
      RectangleMark(
        xStart: .value("Start", scale.axisDistance(nm: chartPoints[index].distanceNM)),
        xEnd: .value("End", scale.axisDistance(nm: chartPoints[nextIndex].distanceNM)),
        yStart: .value("Base", axisFieldElevation),
        yEnd: .value(
          "ImpactTerrain",
          scale.axisAltitude(
            ft: isImpact ? max(terrain[index], terrain[nextIndex]) : fieldElevationFt
          )
        )
      )
      .foregroundStyle(Color.red.opacity(isImpact ? 0.6 : 0))
    }
  }

  @ChartContentBuilder private var obstacleLayer: some ChartContent {
    ForEach(Array(terrainPath.points.enumerated()), id: \.offset) { _, point in
      if let obstacleFt = point.maxObstacleHeightFt, obstacleFt > fieldElevationFt {
        let terrainFt = point.drawnTerrainElevationFt(fieldElevationFt: fieldElevationFt)
        let airborne =
          point.aircraftAltitudeFt > fieldElevationFt + Self.screenHeightFt
        let violated = airborne && point.aircraftAltitudeFt <= obstacleFt
        let x = scale.axisDistance(nm: point.distanceNM),
          terrainTop = scale.axisAltitude(ft: terrainFt),
          obstacleTop = scale.axisAltitude(ft: obstacleFt)
        if violated {
          RuleMark(
            x: .value("Distance", x),
            yStart: .value("Terrain", terrainTop),
            yEnd: .value("Obstacle", obstacleTop)
          )
          .lineStyle(StrokeStyle(lineWidth: 2.5))
          .foregroundStyle(.red)
        } else {
          RuleMark(
            x: .value("Distance", x),
            yStart: .value("Terrain", terrainTop),
            yEnd: .value("Obstacle", obstacleTop)
          )
          .lineStyle(StrokeStyle(lineWidth: 1.5))
          .foregroundStyle(.gray.opacity(0.5))
          RuleMark(
            x: .value("Distance", x),
            yStart: .value("Terrain", terrainTop),
            yEnd: .value("Obstacle", obstacleTop)
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
        x: .value("Waypoint", scale.axisDistance(nm: point.distanceNM)),
        yStart: .value("Base", axisFieldElevation),
        yEnd: .value("Top", axisMaxAltitude)
      )
      .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 4]))
      .foregroundStyle(.blue)
    }
  }

  @ChartContentBuilder private var waypointLabelsLayer: some ChartContent {
    ForEach(waypointPoints, id: \.distanceNM) { point in
      if let name = point.fixName {
        PointMark(
          x: .value("Waypoint", scale.axisDistance(nm: point.distanceNM)),
          y: .value("Top", axisMaxAltitude)
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
          x: .value("Distance", scale.axisDistance(nm: point.distanceNM)),
          y: .value("Freezing level", scale.axisAltitude(ft: point.altitudeFt)),
          series: .value("Series", "freezing")
        )
        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [6, 3]))
        .foregroundStyle(.blue)
      }

      if let freezing = freezingLevelPoints.last {
        PointMark(
          x: .value("Distance", scale.axisDistance(nm: freezing.distanceNM)),
          y: .value("Freezing level", scale.axisAltitude(ft: freezing.altitudeFt))
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
        x: .value("Distance", scale.axisDistance(nm: point.distanceNM)),
        y: .value("Aircraft", scale.axisAltitude(ft: point.aircraftAltitudeFt))
      )
      .foregroundStyle(.purple)
      .lineStyle(StrokeStyle(lineWidth: 3))
    }
  }

  /// The rule and readout for the sample being scrubbed over.
  @ChartContentBuilder private var selectionLayer: some ChartContent {
    if let selectedPoint {
      RuleMark(x: .value("Selection", scale.axisDistance(nm: selectedPoint.distanceNM)))
        .lineStyle(StrokeStyle(lineWidth: 1))
        .foregroundStyle(.gray.opacity(Self.selectionRuleOpacity))
        .annotation(
          position: .top,
          spacing: 0,
          overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .plot))
        ) {
          TerrainProfileCallout(point: selectedPoint, scale: scale)
        }
    }
  }

  // MARK: - Helpers

  private var chartPoints: [ProcedureTerrainPath.Point] {
    terrainPath.points
  }

  private var filledTerrainFt: [Double] {
    chartPoints.map { $0.drawnTerrainElevationFt(fieldElevationFt: fieldElevationFt) }
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

  // Everything the chart reasons about — violations, terrain impacts — is decided in the path's own
  // feet, so the field is read in feet once here and the checks below compare against it.
  private var fieldElevationFt: Double { fieldElevation.converted(to: .feet).value }

  /// The units the chart plots in, which are the pilot's rather than the path's.
  private var scale: TerrainProfileScale {
    .init(heightUnit: heightUnit, distanceUnit: distanceUnit)
  }

  private var axisFieldElevation: Double { scale.axisAltitude(fieldElevation) }

  private var axisMaxAltitude: Double { scale.axisAltitude(maxAltitude) }

  private var axisMaxDistance: Double { scale.axisDistance(nm: maxDistanceNM) }

  /// The sample the scrub has settled on, snapped from wherever the finger actually is.
  private var selectedPoint: ProcedureTerrainPath.Point? {
    guard let selectedDistance else { return nil }
    return terrainPath.point(nearestToDistanceNM: scale.distanceNM(atAxisValue: selectedDistance))
  }

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
    let text = altitudeText(altitude)
    let triangleWidth: CGFloat = 10
    let triangleHeight: CGFloat = 8
    let halfHeight = triangleHeight / 2
    let color: Color = violated ? .red : .blue

    PointMark(
      x: .value("Fix", scale.axisDistance(nm: distanceNM)),
      y: .value("Restriction", scale.axisAltitude(altitude))
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
    altitude.converted(to: heightUnit).formatted(.height)
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

    // Plotted values, in the same units the visible axes carry.
    let distances: [Double]
    let aircraftAltitudes: [Double]
    let terrainAltitudes: [Double]
    let fieldElevation: Double
    let maxDistance: Double
    let maxAltitude: Double

    /// The units the values above are in, which the axis titles and spoken values are read from.
    let scale: TerrainProfileScale

    private var distanceAxis: AXNumericDataAxisDescriptor {
      let unit = scale.distanceUnit
      return AXNumericDataAxisDescriptor(
        title: String(localized: "Distance (\(unit.symbol))"),
        range: nonDegenerateRange(lowerBound: 0, upperBound: maxDistance),
        gridlinePositions: [],
        valueDescriptionProvider: { Measurement(value: $0, unit: unit).formatted(.distance) }
      )
    }

    private var altitudeAxis: AXNumericDataAxisDescriptor {
      let unit = scale.heightUnit
      return AXNumericDataAxisDescriptor(
        title: String(localized: "Altitude MSL (\(unit.symbol))"),
        range: nonDegenerateRange(lowerBound: fieldElevation, upperBound: maxAltitude),
        gridlinePositions: [],
        valueDescriptionProvider: { Measurement(value: $0, unit: unit).formatted(.height) }
      )
    }

    private var climbPathSeries: AXDataSeriesDescriptor {
      AXDataSeriesDescriptor(
        name: String(localized: "Climb path"),
        isContinuous: true,
        dataPoints: zip(distances, aircraftAltitudes).map { distance, altitude in
          AXDataPoint(x: distance, y: altitude)
        }
      )
    }

    private var terrainSeries: AXDataSeriesDescriptor {
      AXDataSeriesDescriptor(
        name: String(localized: "Terrain"),
        isContinuous: true,
        dataPoints: zip(distances, terrainAltitudes).map { distance, terrain in
          AXDataPoint(x: distance, y: terrain)
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
  var terrainPath = ProcedureTerrainPath.preview

  var body: some View {
    TerrainProfileChartView(
      terrainPath: terrainPath,
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

/// A stretch with no terrain downloaded under it, which scrubbing reports as unknown rather than as
/// ground at field elevation.
#Preview("Missing terrain") {
  ChartPreview(layer: .none, terrainPath: .previewMissingTerrain)
}
