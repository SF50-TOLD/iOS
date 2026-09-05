import MeasurementKit
import SF50_Shared
import SwiftUI

/// What the profile says about the sample being scrubbed over.
///
/// Where the region under the path has not been downloaded, only the distance is stated. An
/// altitude above a ground nothing is known about is not a number this chart will show.
struct TerrainProfileCallout: View {

  // MARK: - Constants

  private static let cornerRadiusPts: CGFloat = 5,
    horizontalPaddingPts: CGFloat = 5,
    verticalPaddingPts: CGFloat = 3

  private static let labelSpacingPts: CGFloat = 6,
    rowSpacingPts: CGFloat = 1

  private static let borderOpacity = 0.25

  // MARK: - Inputs

  /// The sample being scrubbed over.
  let point: ProcedureTerrainPath.Point

  /// The units the chart is plotted in, which the readout is stated in.
  let scale: TerrainProfileScale

  /// How far along the path the scrubbed sample stands, on the chart's own distance axis.
  private var axisDistance: Double { scale.axisDistance(nm: point.distanceNM) }

  var body: some View {
    Grid(
      alignment: .leading,
      horizontalSpacing: Self.labelSpacingPts,
      verticalSpacing: Self.rowSpacingPts
    ) {
      GridRow {
        Text("Dist")
          .foregroundStyle(.secondary)
        // A number beside the axis's own symbol, rather than a measurement format style, which
        // spells nautical miles "nmi" against an axis that says "NM". Verbatim because it is a
        // reading rather than a phrase: the number localizes itself and the symbol is standard.
        Text(verbatim: "\(axisDistance.formatted(.distance)) \(scale.distanceUnit.symbol)")
          .gridColumnAlignment(.trailing)
      }
      if let altitudeAGL = point.altitudeAGL {
        GridRow {
          Text("Alt MSL")
            .foregroundStyle(.secondary)
          Text(point.altitudeMSL.converted(to: scale.heightUnit), format: .height)
        }
        GridRow {
          Text("Alt AGL")
            .foregroundStyle(.secondary)
          Text(altitudeAGL.converted(to: scale.heightUnit), format: .height)
            // Below the terrain it is standing on, which is the answer the profile exists to give.
            .foregroundStyle(altitudeAGL.value < 0 ? Color.red : .primary)
        }
      }
      if let fixName = point.fixName {
        GridRow {
          Text(fixName)
            .foregroundStyle(.blue)
            .gridCellColumns(2)
        }
      }
      if let restriction = point.altitudeRestriction {
        GridRow {
          Text(restriction.description(in: scale.heightUnit))
            .foregroundStyle(.secondary)
            .gridCellColumns(2)
        }
      }
    }
    .font(.caption2)
    .monospacedDigit()
    .padding(.horizontal, Self.horizontalPaddingPts)
    .padding(.vertical, Self.verticalPaddingPts)
    .background(Color(.systemBackground), in: .rect(cornerRadius: Self.cornerRadiusPts))
    .overlay {
      RoundedRectangle(cornerRadius: Self.cornerRadiusPts)
        .strokeBorder(.secondary.opacity(Self.borderOpacity))
    }
    // The chart is a single element behind its own `AXChartDescriptor`, which already plays both
    // series as an audio graph; a scrub readout would be a second voice for the same numbers.
    .accessibilityHidden(true)
  }
}

// periphery:ignore - consumed only by the #Preview macros below
private struct CalloutPreview: View {
  var terrainElevationFt: Double? = 2568
  var aircraftAltitudeFt: Double = 3808
  var fixName: String?
  var altitudeRestriction: AltitudeRestriction?
  var heightUnit = UnitLength.feet
  var distanceUnit = UnitLength.nauticalMiles

  var body: some View {
    TerrainProfileCallout(
      point: .preview(
        aircraftAltitudeFt: aircraftAltitudeFt,
        altitudeRestriction: altitudeRestriction,
        fixName: fixName,
        terrainElevationFt: terrainElevationFt
      ),
      scale: .init(heightUnit: heightUnit, distanceUnit: distanceUnit)
    )
    .padding()
  }
}

#Preview("Above the terrain") {
  CalloutPreview()
}

#Preview("Below the ridge") {
  CalloutPreview(aircraftAltitudeFt: 2328)
}

#Preview("At a fix") {
  CalloutPreview(
    fixName: "LINDZ",
    altitudeRestriction: .atOrAbove(.init(value: 4000, unit: .feet))
  )
}

/// The region under this stretch of the path has not been downloaded, so nothing is known about the
/// ground here — and no height above it is claimed.
#Preview("No terrain data") {
  CalloutPreview(terrainElevationFt: nil)
}

#Preview("Metric") {
  CalloutPreview(
    fixName: "LINDZ",
    altitudeRestriction: .between(
      min: .init(value: 3000, unit: .feet),
      max: .init(value: 5000, unit: .feet)
    ),
    heightUnit: .meters,
    distanceUnit: .kilometers
  )
}
