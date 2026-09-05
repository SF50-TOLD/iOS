import Charts
import SF50_Shared
import SwiftUI

/// The weather field drawn behind a climb profile's terrain and flight path.
///
/// Sits in the chart's background so terrain and the climb path stay legible over it. The field is
/// sampled in vertical strips a few points wide: within a strip the atmosphere is read continuously,
/// and between strips it is read across whichever columns bracket that distance.
struct WeatherFieldLayer: View {

  // MARK: - Constants

  /// How wide a sampled strip is. Narrow enough that a field reads as continuous, wide enough that a
  /// full-width chart is a few dozen samples rather than a few hundred.
  private static let stripWidth: CGFloat = 6

  /// How tall a sampled block is where the field is drawn as blocks rather than a gradient.
  private static let sampleHeight: CGFloat = 4

  /// Where up each strip the temperature gradient is sampled.
  private static let gradientSamples = Array(stride(from: 0 as CGFloat, through: 1, by: 0.1))

  /// How thick a cloud deck is drawn.
  ///
  /// A fixed thickness, because nothing reports how deep a deck is: the model gives coverage at a
  /// pressure level and says nothing about the air between levels. The bar marks the altitude the
  /// cloud was reported for, and its height is a drawing convention rather than a depth.
  private static let cloudDeckThickness: CGFloat = 6

  private static let cloudTint = Color.gray.opacity(0.6)

  /// How many decks the dash offset cycles over before repeating.
  private static let dashPhaseCycle = 3

  /// How far each deck shifts its dash pattern from the one below.
  private static let dashPhaseStep: CGFloat = 5

  /// The colour the icing band is drawn in, before its strength decides how solid it is.
  static let icingHue = Color.purple

  /// How solid the icing band is drawn at its weakest and strongest.
  ///
  /// The weak end has to be visible without claiming much, since it marks air the model only
  /// hints at; the strong end stays light enough for the climb path to read over it.
  private static let icingMinOpacity = 0.14,
    icingMaxOpacity = 0.36

  /// How solid the temperature field is drawn.
  ///
  /// Faint enough that terrain, obstacles, and the climb path read over it — the field is context
  /// for the path, not the subject of the chart.
  private static let fieldOpacity = 0.32

  /// The temperature scale, coldest first, diverging about freezing.
  private static let temperatureScale: [(celsius: Double, color: Color)] = [
    (-40, .init(red: 0.36, green: 0.20, blue: 0.62)),
    (-20, .init(red: 0.20, green: 0.38, blue: 0.78)),
    (0, .init(red: 0.45, green: 0.75, blue: 0.88)),
    (15, .init(red: 0.95, green: 0.85, blue: 0.55)),
    (30, .init(red: 0.90, green: 0.55, blue: 0.25)),
    (45, .init(red: 0.78, green: 0.25, blue: 0.20))
  ]

  // MARK: - Inputs

  /// The chart to draw behind, for mapping distances and altitudes onto the plot area.
  let proxy: ChartProxy

  /// The atmosphere along the path.
  let atmosphere: PathAtmosphere

  /// Which field to draw.
  let layer: WeatherProfileLayer

  /// The units the chart plots in, which positions read out of the proxy are interpreted through.
  let scale: TerrainProfileScale

  var body: some View {
    GeometryReader { geometry in
      if let plotFrame = proxy.plotFrame, layer.needsAtmosphere, !atmosphere.isEmpty {
        let rect = geometry[plotFrame]
        Canvas(opaque: false) { context, _ in
          draw(in: &context, rect: rect)
        }
        .accessibilityHidden(true)
      }
    }
  }

  // MARK: - Scale

  /// The colour a temperature is drawn in, interpolated between the scale's anchors.
  ///
  /// Returned at full strength. The field is faded where it is drawn, so a legend can key the same
  /// scale in solid colour without having to undo an opacity baked in here.
  static func color(forTemperatureC temperatureC: Double) -> Color {
    guard let first = temperatureScale.first, let last = temperatureScale.last else {
      return .clear
    }
    if temperatureC <= first.celsius { return first.color }
    if temperatureC >= last.celsius { return last.color }

    for (lower, upper) in zip(temperatureScale, temperatureScale.dropFirst())
    where temperatureC >= lower.celsius && temperatureC <= upper.celsius {
      let fraction = (temperatureC - lower.celsius) / (upper.celsius - lower.celsius)
      return lower.color.mix(with: upper.color, by: fraction)
    }
    return last.color
  }

  /// The colour an icing band of a given strength is drawn in.
  ///
  /// - Parameter strength: How far into the icing band the air is, from zero to one.
  /// - Returns: The tint to fill with.
  static func icingTint(strength: Double) -> Color {
    icingHue.opacity(icingMinOpacity + (icingMaxOpacity - icingMinOpacity) * strength)
  }

  /// How far along its dash pattern a deck starts, so stacked decks don't line their gaps up.
  private static func dashPhase(forDeck deck: Int) -> CGFloat {
    CGFloat(deck % dashPhaseCycle) * dashPhaseStep
  }

  // MARK: - Drawing

  private func draw(in context: inout GraphicsContext, rect: CGRect) {
    switch layer {
      case .none: break
      case .temperature: drawTemperature(in: &context, rect: rect)
      case .clouds: drawClouds(in: &context, rect: rect)
      case .icing: drawIcing(in: &context, rect: rect)
    }
  }

  /// Fills each strip with a vertical gradient of the temperatures reported through it.
  private func drawTemperature(in context: inout GraphicsContext, rect: CGRect) {
    var context = context
    context.opacity = Self.fieldOpacity

    forEachStrip(in: rect) { strip, distanceNM in
      // Sampled downwards, since a gradient's stops have to run in order and the gradient starts
      // at the top of the strip.
      let stops = Self.gradientSamples.compactMap { fraction -> Gradient.Stop? in
        let y = strip.minY + strip.height * fraction
        guard let level = level(atDistanceNM: distanceNM, y: y, rect: rect),
          let temperatureC = level.temperature?.converted(to: .celsius).value
        else { return nil }
        return .init(color: Self.color(forTemperatureC: temperatureC), location: fraction)
      }
      guard stops.count > 1 else { return }

      context.fill(
        .init(strip),
        with: .linearGradient(
          .init(stops: stops),
          startPoint: .init(x: strip.midX, y: strip.minY),
          endPoint: .init(x: strip.midX, y: strip.maxY)
        )
      )
    }
  }

  /// Shades the band where the air is cold enough and damp enough to ice, more solidly where it
  /// ices more readily.
  private func drawIcing(in context: inout GraphicsContext, rect: CGRect) {
    forEachStrip(in: rect) { strip, distanceNM in
      var y = strip.minY
      while y < strip.maxY {
        let height = min(Self.sampleHeight, strip.maxY - y)
        if let level = level(atDistanceNM: distanceNM, y: y + height / 2, rect: rect),
          level.isIcing
        {
          context.fill(
            .init(.init(x: strip.minX, y: y, width: strip.width, height: height)),
            with: .color(Self.icingTint(strength: level.icingStrength))
          )
        }
        y += height
      }
    }
  }

  /// Draws a bar at each altitude cloud was reported for, solid for an overcast and opening up as
  /// the coverage thins.
  ///
  /// Only the reported altitudes are drawn. Coverage between two levels is an interpolation, and
  /// filling the gap with it would draw a deck thousands of feet deep from a model that never said
  /// how deep any deck is — thicker where the levels happen to be further apart.
  ///
  /// Each deck's dash pattern is offset from the one below it, so stacked decks read as separate
  /// layers rather than as a picket fence of aligned gaps.
  private func drawClouds(in context: inout GraphicsContext, rect: CGRect) {
    for (deck, altitude) in atmosphere.reportedAltitudes.enumerated() {
      guard let y = position(forAltitude: altitude, rect: rect) else { continue }
      for run in coverageRuns(at: altitude, rect: rect) {
        var bar = Path()
        bar.move(to: .init(x: run.minX, y: y))
        bar.addLine(to: .init(x: run.maxX, y: y))
        context.stroke(
          bar,
          with: .color(Self.cloudTint),
          style: .init(
            lineWidth: Self.cloudDeckThickness,
            dash: run.cover.dash,
            dashPhase: Self.dashPhase(forDeck: deck)
          )
        )
      }
    }
  }

  /// Groups the strips at one altitude into stretches sharing a coverage category.
  private func coverageRuns(at altitude: Measurement<UnitLength>, rect: CGRect) -> [CoverageRun] {
    var runs = [CoverageRun]()
    forEachStrip(in: rect) { strip, distanceNM in
      guard
        let cover = atmosphere.level(atDistanceNM: distanceNM, altitude: altitude)?.skyCover
      else { return }
      if var last = runs.last, last.cover == cover, last.maxX >= strip.minX - 0.5 {
        last.maxX = strip.maxX
        runs[runs.count - 1] = last
      } else {
        runs.append(.init(minX: strip.minX, maxX: strip.maxX, cover: cover))
      }
    }
    return runs
  }

  // MARK: - Sampling

  private func forEachStrip(in rect: CGRect, _ body: (CGRect, Double) -> Void) {
    var x = rect.minX
    while x < rect.maxX {
      let width = min(Self.stripWidth, rect.maxX - x)
      let strip = CGRect(x: x, y: rect.minY, width: width, height: rect.height)
      if let axisDistance: Double = proxy.value(atX: strip.midX - rect.minX) {
        body(strip, scale.distanceNM(atAxisValue: axisDistance))
      }
      x += width
    }
  }

  private func level(
    atDistanceNM distanceNM: Double,
    y: CGFloat,
    rect: CGRect
  ) -> AtmosphericProfile.Level? {
    guard let axisAltitude: Double = proxy.value(atY: y - rect.minY) else { return nil }
    return atmosphere.level(
      atDistanceNM: distanceNM,
      altitude: scale.altitude(atAxisValue: axisAltitude)
    )
  }

  /// Where an altitude falls in the plot area, or `nil` if it falls outside it.
  private func position(forAltitude altitude: Measurement<UnitLength>, rect: CGRect) -> CGFloat? {
    guard let offset = proxy.position(forY: scale.axisAltitude(altitude)) else { return nil }
    let y = rect.minY + offset
    return (rect.minY...rect.maxY).contains(y) ? y : nil
  }

  // MARK: - Subtypes

  /// A stretch of one altitude sharing a cloud coverage category.
  private struct CoverageRun {
    let minX: CGFloat
    var maxX: CGFloat
    let cover: SkyCover
  }
}
