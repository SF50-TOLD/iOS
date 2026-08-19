import MeasurementKit
import SwiftUI

/// A wind barb drawn for the component of the wind along a flight path.
///
/// A conventional barb points into the wind on a plan view, where the page has a compass direction.
/// A climb profile's page does not — across is distance flown and up is altitude — so this barb is
/// resolved against the track instead: the shaft lies along the path, pointing aft for a headwind
/// and forward for a tailwind, and the feathers count the knots of that component. Crosswind is not
/// drawn, having nothing to say about a climb gradient.
///
/// Feathers follow the station-model convention: a pennant for fifty knots, a full barb for ten, a
/// half barb for five, and a bare circle for a component under five.
public struct WindBarb: View {

  // MARK: - Constants

  private static let strokeWidth: CGFloat = 1.2
  private static let calmDiameter: CGFloat = 7
  private static let barbHeight: CGFloat = 16
  private static let extrapolatedOpacity = 0.5

  // MARK: - Inputs

  /// The along-track component: positive for a tailwind, negative for a headwind.
  public let component: Measurement<UnitSpeed>

  /// How the barb is tinted — muted where the wind is carried down below the lowest reported level.
  public let isExtrapolated: Bool

  @ScaledMetric(relativeTo: .caption)
  private var shaftLength: CGFloat = 26

  private var opacity: Double { isExtrapolated ? Self.extrapolatedOpacity : 1 }

  /// The component in the knots the station-model convention counts feathers in.
  private var componentKts: Double { component.converted(to: .knots).value }

  public var body: some View {
    Group {
      if Feathers(componentKts: componentKts).isCalm {
        Circle()
          .strokeBorder(lineWidth: Self.strokeWidth)
          .frame(width: Self.calmDiameter, height: Self.calmDiameter)
      } else {
        BarbShape(componentKts: componentKts)
          .stroke(style: .init(lineWidth: Self.strokeWidth, lineCap: .round, lineJoin: .round))
          .frame(width: shaftLength, height: Self.barbHeight)
      }
    }
    // A concrete colour, not the semantic style: inside a chart's symbol the semantic style
    // resolves against the plot's own hierarchy and comes out blue. Secondary rather than
    // primary, so a field of barbs sits behind the climb path rather than competing with it.
    .foregroundStyle(Color.secondary)
    .opacity(opacity)
    .accessibilityLabel(accessibilityLabel)
  }

  private var accessibilityLabel: String {
    let speed = component.magnitude
    if Feathers(componentKts: componentKts).isCalm {
      return String(localized: "Wind along course under 5 knots")
    }
    return componentKts < 0
      ? String(localized: "Headwind \(speed, format: .speed)")
      : String(
        localized: "Tailwind \(speed, format: .speed)"
      )
  }

  /// Creates a barb for a wind component along a path.
  ///
  /// - Parameters:
  ///   - component: The along-track component: positive downwind, negative against.
  ///   - isExtrapolated: Whether the wind was carried down from a higher reported level.
  public init(component: Measurement<UnitSpeed>, isExtrapolated: Bool) {
    self.component = component
    self.isExtrapolated = isExtrapolated
  }

  // MARK: - Subtypes

  /// How many of each feather a wind speed is drawn with.
  ///
  /// Speeds are rounded to the nearest five knots first, the way a station model reports them, so a
  /// twelve-knot wind draws the same single barb a ten-knot one does.
  struct Feathers: Equatable {

    /// Fifty-knot pennants.
    let pennants: Int

    /// Ten-knot barbs.
    let full: Int

    /// A trailing five-knot half barb.
    let half: Bool

    /// Whether the wind rounds to nothing, and is drawn as a bare circle.
    var isCalm: Bool { pennants == 0 && full == 0 && !half }

    /// Decomposes a wind speed into the feathers that represent it.
    ///
    /// - Parameter componentKts: The wind component; its sign is ignored.
    init(componentKts: Double) {
      var fives = Int((componentKts.magnitude / 5).rounded())
      pennants = fives / 10
      fives -= pennants * 10
      full = fives / 2
      half = fives % 2 == 1
    }
  }

  /// The shaft and its feathers, drawn left to right with the barbs on top.
  ///
  /// The shape is always drawn pointing right and mirrored by the caller's sign, so the feather
  /// geometry is written once.
  private struct BarbShape: Shape {

    /// How far along the shaft one feather's root sits from the next.
    private static let featherSpacing: CGFloat = 4

    /// How far a full barb rises from the shaft, as a fraction of the shape's height.
    private static let featherRise: CGFloat = 0.85

    /// How far a pennant's trailing edge sits from its leading one.
    private static let pennantWidth: CGFloat = 5

    let componentKts: Double

    func path(in rect: CGRect) -> Path {
      let feathers = Feathers(componentKts: componentKts)
      let isTailwind = componentKts >= 0

      var path = Path()
      // Drawn tip-right, then flipped for a headwind so the shaft points aft.
      path.move(to: .init(x: rect.minX, y: rect.maxY))
      path.addLine(to: .init(x: rect.maxX, y: rect.maxY))

      var offset = rect.maxX
      let top = rect.maxY - rect.height * Self.featherRise

      for _ in 0..<feathers.pennants {
        path.move(to: .init(x: offset, y: rect.maxY))
        path.addLine(to: .init(x: offset - Self.pennantWidth / 2, y: top))
        path.addLine(to: .init(x: offset - Self.pennantWidth, y: rect.maxY))
        path.closeSubpath()
        offset -= Self.pennantWidth + Self.featherSpacing / 2
      }

      for _ in 0..<feathers.full {
        path.move(to: .init(x: offset, y: rect.maxY))
        path.addLine(to: .init(x: offset - Self.featherSpacing, y: top))
        offset -= Self.featherSpacing
      }

      if feathers.half {
        // A half barb never stands at the tip; a lone one is set in by a full barb's width.
        if offset == rect.maxX { offset -= Self.featherSpacing }
        path.move(to: .init(x: offset, y: rect.maxY))
        path.addLine(to: .init(x: offset - Self.featherSpacing / 2, y: (top + rect.maxY) / 2))
      }

      guard !isTailwind else { return path }
      return path.applying(.init(scaleX: -1, y: 1).translatedBy(x: -rect.width, y: 0))
    }
  }
}

#Preview("Along-track wind barbs") {
  Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
    ForEach([-55.0, -25.0, -12.0, -5.0, 3.0, 15.0, 47.0, 105.0], id: \.self) { kts in
      let component = Measurement(value: kts, unit: UnitSpeed.knots)
      GridRow {
        Text(component, format: .measurement(width: .narrow))
          .font(.caption)
          .monospacedDigit()
        WindBarb(component: component, isExtrapolated: false)
        WindBarb(component: component, isExtrapolated: true)
      }
    }
  }
  .padding()
}
