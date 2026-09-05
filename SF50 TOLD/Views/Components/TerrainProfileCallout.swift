import MeasurementKit
import SF50_Shared
import SwiftUI

/// What the profile says about the sample being scrubbed over.
///
/// Where the region under the path has not been downloaded, the height above the ground is left
/// out: an altitude above a ground nothing is known about is not a number this chart will show. The
/// altitude MSL is stated regardless, being read off the flown profile rather than off the terrain.
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
      GridRow {
        Text("Alt MSL")
          .foregroundStyle(.secondary)
        Text(point.altitudeMSL.converted(to: scale.heightUnit), format: .height)
      }
      if let altitudeAGL = point.altitudeAGL {
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

extension AltitudeRestriction {
  /// How the restriction reads to a pilot, in the unit they chose to see altitudes in.
  ///
  /// Phrased in the app rather than alongside the model it describes: `SF50 Shared` is a framework
  /// with no string catalog of its own, and prose written there is never collected for translation.
  ///
  /// - Parameter unit: The unit to state the altitudes in.
  /// - Returns: A phrase naming the constraint and the altitudes it holds the aircraft to.
  fileprivate func description(in unit: UnitLength) -> String {
    switch self {
      case .at(let altitude):
        return String(localized: "At \(altitude.converted(to: unit), format: .height)")
      case .atOrAbove(let altitude):
        return String(localized: "At or above \(altitude.converted(to: unit), format: .height)")
      case .atOrBelow(let altitude):
        return String(localized: "At or below \(altitude.converted(to: unit), format: .height)")
      case .between(let minimum, let maximum):
        let low = minimum.converted(to: unit), high = maximum.converted(to: unit)
        return String(localized: "Between \(low, format: .height) and \(high, format: .height)")
    }
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
/// ground here — and no height above it is claimed, though the altitude MSL is still stated.
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
