import Defaults
import SF50_Shared
import SwiftUI

/// The key to whichever weather field a climb profile is showing.
///
/// Swift Charts builds a legend from the styles it maps itself, and the fields are drawn into the
/// chart's background rather than as marks, so their key is drawn here instead.
///
/// The wind barbs have no key: a barb reads as a wind to anyone flying the aeroplane, and a legend
/// for it would say less than the chart already does.
struct WeatherLayerLegend: View {

  /// The field being shown.
  let layer: WeatherProfileLayer

  /// The temperatures the visible part of the field spans, if it is the temperature field.
  let temperatureRange: ClosedRange<Measurement<UnitTemperature>>?

  /// Whether the freezing level is drawn on the chart, and so wants keying.
  let showsFreezingLevel: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      switch layer {
        case .none: EmptyView()
        case .temperature:
          if let temperatureRange { TemperatureKey(range: temperatureRange) }
        case .clouds: CloudKey()
        case .icing: IcingKey()
      }
      if showsFreezingLevel {
        FreezingLevelKey()
      }
    }
    .font(.caption2)
    // The absolute label colour: a section footer already dims what it holds, and the hierarchical
    // style compounds with that into a gray too faint to read against the grouped background.
    .foregroundStyle(Color.secondary)
  }
}

/// How large a legend draws its swatches.
private enum LegendMetrics {
  static let barHeight: CGFloat = 6
  static let swatchWidth: CGFloat = 22
}

/// The temperatures the visible field spans, keyed by the scale it is drawn in.
private struct TemperatureKey: View {

  let range: ClosedRange<Measurement<UnitTemperature>>

  @Default(.temperatureUnit)
  private var temperatureUnit

  private var stops: [Gradient.Stop] {
    let span = range.upperBound - range.lowerBound
    return stride(from: 0.0, through: 1.0, by: 0.1).map { fraction in
      let temperature = range.lowerBound + span * fraction
      return .init(
        color: WeatherFieldLayer.color(
          forTemperatureC: temperature.converted(to: .celsius).value
        ),
        location: fraction
      )
    }
  }

  var body: some View {
    HStack(spacing: 6) {
      Text(label(range.lowerBound))
      LinearGradient(stops: stops, startPoint: .leading, endPoint: .trailing)
        .frame(height: LegendMetrics.barHeight)
        .clipShape(.rect(cornerRadius: LegendMetrics.barHeight / 2))
      Text(label(range.upperBound))
    }
    .monospacedDigit()
  }

  private func label(_ temperature: Measurement<UnitTemperature>) -> String {
    temperature
      .converted(to: temperatureUnit)
      .formatted(
        .measurement(
          width: .narrow,
          usage: .asProvided,
          numberFormatStyle: .number
            .precision(.fractionLength(0))
        )
      )
  }
}

/// The dash pattern each coverage category is drawn with.
private struct CloudKey: View {
  var body: some View {
    HStack(spacing: 12) {
      ForEach(SkyCover.allCases, id: \.self) { cover in
        HStack(spacing: 4) {
          LegendRule()
            .stroke(
              Color.gray,
              style: .init(lineWidth: LegendMetrics.barHeight, dash: cover.dash)
            )
            .frame(width: LegendMetrics.swatchWidth, height: LegendMetrics.barHeight)
          Text(cover.label)
        }
      }
    }
  }
}

/// The band the icing field shades, from its faintest to its strongest.
private struct IcingKey: View {

  /// How solid the ends of the key are drawn.
  ///
  /// Stronger than the field itself, for the same reason the temperature key is: a swatch this
  /// small has to carry its colour where a band the height of the chart does not.
  private static let minOpacity = 0.22,
    maxOpacity = 0.55

  var body: some View {
    HStack(spacing: 6) {
      LinearGradient(
        colors: [
          WeatherFieldLayer.icingHue.opacity(Self.minOpacity),
          WeatherFieldLayer.icingHue.opacity(Self.maxOpacity)
        ],
        startPoint: .leading,
        endPoint: .trailing
      )
      .frame(width: LegendMetrics.swatchWidth, height: LegendMetrics.barHeight)
      .clipShape(.rect(cornerRadius: 2))
      Text("Below freezing + visible moisture")
    }
  }
}

/// The rule the chart draws the freezing level with.
private struct FreezingLevelKey: View {

  /// The dash the chart rules the freezing level with, repeated here so the two match.
  private static let dash: [CGFloat] = [6, 3]

  var body: some View {
    HStack(spacing: 6) {
      LegendRule()
        .stroke(Color.blue, style: .init(lineWidth: 1.5, dash: Self.dash))
        .frame(width: LegendMetrics.swatchWidth, height: LegendMetrics.barHeight)
      Text("Freezing level")
    }
  }
}

/// A horizontal rule, so a dash pattern can be shown as the key to a coverage category.
private struct LegendRule: Shape {
  func path(in rect: CGRect) -> Path {
    Path { path in
      path.move(to: .init(x: rect.minX, y: rect.midY))
      path.addLine(to: .init(x: rect.maxX, y: rect.midY))
    }
  }
}

#Preview("Legends") {
  VStack(alignment: .leading, spacing: 16) {
    WeatherLayerLegend(
      layer: .temperature,
      temperatureRange: .init(value: -12, unit: .celsius)...(.init(value: 21, unit: .celsius)),
      showsFreezingLevel: true
    )
    WeatherLayerLegend(layer: .clouds, temperatureRange: nil, showsFreezingLevel: false)
    WeatherLayerLegend(layer: .icing, temperatureRange: nil, showsFreezingLevel: true)
  }
  .padding()
}
