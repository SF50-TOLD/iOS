import SF50_Shared
import SwiftUI

/// The weather controls for a terrain profile chart, as a pair of pills in its top-left corner.
///
/// Inside the chart's box, so the controls read as belonging to the chart they draw on. A pull-down
/// each, and no enclosing popover: a menu opened from inside a popover presents away from the row
/// that owns it.
struct ProfileWeatherControls: View {

  // MARK: - Constants

  private static let pillSpacing: CGFloat = 6

  // MARK: - Inputs

  /// The field drawn behind the profile.
  @Binding var layer: WeatherProfileLayer

  /// Whether the along-track wind barbs are drawn over it.
  @Binding var showsWindBarbs: Bool

  /// Whether the field layers have anything to draw.
  let fieldLayersAvailable: Bool

  /// Whether a winds aloft forecast covers this flight.
  let hasWindsAloft: Bool

  var body: some View {
    HStack(spacing: Self.pillSpacing) {
      LayerPill(layer: $layer, fieldLayersAvailable: fieldLayersAvailable)
      WindPill(showsWindBarbs: $showsWindBarbs, hasWindsAloft: hasWindsAloft)
    }
    .menuStyle(.button)
    .buttonStyle(.bordered)
    .buttonBorderShape(.capsule)
    .controlSize(.small)
    .font(.caption)
  }
}

/// Picks the field drawn behind the profile.
private struct LayerPill: View {

  @Binding var layer: WeatherProfileLayer

  let fieldLayersAvailable: Bool

  /// What the pill is called: the field it is drawing, or the general name when it is drawing none,
  /// so the chart says what is behind it without being opened.
  private var title: String {
    layer == .none ? String(localized: "Weather") : layer.label
  }

  var body: some View {
    Menu {
      Picker("Weather", selection: $layer) {
        ForEach(WeatherProfileLayer.allCases) { layer in
          Text(layer.label).tag(layer)
        }
      }
      .pickerStyle(.inline)
    } label: {
      PillLabel(title: title)
    }
    // The bordered background is measured once for the label it was built with and is not
    // re-measured when the title changes width, leaving the capsule at its old size — centred in
    // the new frame, with the title spilling out both ends until some unrelated change forces the
    // button to redraw. Re-identifying it on the layer builds a button that measures the new title.
    .id(layer)
    .accessibilityIdentifier("weatherLayerPicker")
    .accessibilityLabel(Text("Weather"))
    .accessibilityValue(Text(layer.label))
    // Every field needs the atmosphere, so with none to draw from the pill has nothing to offer
    // but the layer already showing. A dead control says that better than a note under the chart.
    .disabled(!fieldLayersAvailable)
  }
}

/// Turns the along-track wind barbs on and off.
private struct WindPill: View {

  @Binding var showsWindBarbs: Bool

  let hasWindsAloft: Bool

  var body: some View {
    Menu {
      Picker("Wind", selection: $showsWindBarbs) {
        Text("Off").tag(false)
        Text("On").tag(true)
      }
      .pickerStyle(.inline)
    } label: {
      PillLabel(title: String(localized: "Wind"))
    }
    .accessibilityIdentifier("windBarbsPicker")
    .disabled(!hasWindsAloft)
  }
}

/// A pill's title and the chevron marking it as a pull-down.
private struct PillLabel: View {

  let title: String

  var body: some View {
    HStack(spacing: 2) {
      Text(title)
      Image(systemName: "chevron.down")
        .imageScale(.small)
        .accessibilityHidden(true)
    }
  }
}

#Preview("Everything available") {
  @Previewable @State var layer = WeatherProfileLayer.clouds
  @Previewable @State var showsWindBarbs = true

  ProfileWeatherControls(
    layer: $layer,
    showsWindBarbs: $showsWindBarbs,
    fieldLayersAvailable: true,
    hasWindsAloft: true
  )
}

/// The go-around case: in the air with no connection, so only the barbs are left to offer.
#Preview("No connection") {
  @Previewable @State var layer = WeatherProfileLayer.none
  @Previewable @State var showsWindBarbs = false

  ProfileWeatherControls(
    layer: $layer,
    showsWindBarbs: $showsWindBarbs,
    fieldLayersAvailable: false,
    hasWindsAloft: false
  )
}
