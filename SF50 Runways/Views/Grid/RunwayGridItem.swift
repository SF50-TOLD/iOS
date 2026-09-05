import SF50_Shared
import SwiftUI
import WidgetKit

struct RunwayGridItem: View {
  var runway: RunwaySnapshot
  var performance: RunwayPerformance?
  var operation: SF50_Shared.Operation

  var body: some View {
    HStack(spacing: 2) {
      mark
      Text(runway.name)
        .bold()
        .fixedSize(horizontal: true, vertical: false)
    }
  }

  @ViewBuilder private var mark: some View {
    switch performance?.distance {
      case .value(let measurement), .valueWithUncertainty(let measurement, _):
        if measurement > runway.availableDistance(for: operation) {
          Image(systemName: "x.circle.fill")
            .foregroundColor(.red)
            .accessibilityLabel(insufficientLabel)
        } else {
          Image(systemName: "checkmark.circle.fill")
            .foregroundColor(.green)
            .accessibilityLabel(sufficientLabel)
        }
      case .notAuthorized:
        Image(systemName: "x.circle.fill")
          .foregroundColor(.red)
          .accessibilityLabel("Configuration not authorized")
      case .invalid, .notAvailable:
        Image(systemName: "questionmark.circle.fill")
          .foregroundColor(.gray)
          .accessibilityLabel("Not available")
      case .offscaleHigh:
        Image(systemName: "x.circle.fill")
          .foregroundColor(.red)
          .accessibilityLabel("Offscale high")
      case .offscaleLow:
        Image(systemName: "x.circle.fill")
          .foregroundColor(.gray)
          .accessibilityLabel("Offscale low")
      case .none:
        Image(systemName: "questionmark.circle.fill")
          .foregroundColor(.gray)
          .accessibilityLabel("Unknown")
    }
  }

  private var sufficientLabel: Text {
    switch operation {
      case .takeoff: Text("Available takeoff distance sufficient")
      case .landing: Text("Available landing distance sufficient")
    }
  }

  private var insufficientLabel: Text {
    switch operation {
      case .takeoff: Text("Available takeoff distance insufficient")
      case .landing: Text("Available landing distance insufficient")
    }
  }
}
