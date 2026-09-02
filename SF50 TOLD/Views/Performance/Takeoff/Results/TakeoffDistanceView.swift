import Defaults
import SF50_Shared
import SwiftUI

struct TakeoffDistanceView: View {
  @Environment(TakeoffPerformanceViewModel.self)
  private var performance

  @Default(.runwayLengthUnit)
  private var runwayLengthUnit

  var body: some View {
    LabeledContent(
      content: {
        InterpolationView(
          value: performance.takeoffDistance,
          maximum: performance.availableTakeoffDistance,
          displayValue: {
            Text($0.converted(to: runwayLengthUnit), format: .length).fontWeight(.semibold)
          },
          displayUncertainty: { Text("±\($0.converted(to: runwayLengthUnit), format: .length)") }
        )
        .animation(.default, value: performance.takeoffDistance)
        .accessibilityIdentifier("takeoffDistanceValue")
        .accessibilityCustomContent(.sufficiency, sufficiencyContent, importance: .high)
        .accessibilityCustomContent(.availableDistance, availableDistanceContent)
      },
      label: {
        Text("Total Distance")
        Text("over a 50-foot obstacle")
          .font(.caption)
          .fixedSize(horizontal: false, vertical: true)
      }
    )
  }
}

// MARK: - Accessibility

extension TakeoffDistanceView {
  /// The runway-length comparison the value otherwise signals with red text alone.
  fileprivate var sufficiencyContent: Text? {
    guard let available = performance.availableTakeoffDistance else { return nil }

    let required: Measurement<UnitLength>
    switch performance.takeoffDistance {
      case .value(let distance), .valueWithUncertainty(let distance, _): required = distance
      case .invalid, .notAvailable, .notAuthorized, .offscaleHigh, .offscaleLow: return nil
    }

    return required > available
      ? Text("Available takeoff distance insufficient")
      : Text("Available takeoff distance sufficient")
  }

  fileprivate var availableDistanceContent: Text? {
    guard let available = performance.availableTakeoffDistance else { return nil }
    return Text(available.converted(to: runwayLengthUnit), format: .length)
  }
}

extension AccessibilityCustomContentKey {
  fileprivate static var sufficiency: Self { .init("Runway") }
  fileprivate static var availableDistance: Self { .init("Takeoff distance available") }
}

#Preview("Possible") {
  PreviewView(insert: .KSQL) { preview in
    let runway = try preview.load(airportID: "SQL", runway: "30")!
    preview.setTakeoff(runway: runway)

    return List {
      TakeoffDistanceView()
    }
    .environment(TakeoffPerformanceViewModel(container: preview.container))
  }
}

#Preview("Impossible") {
  PreviewView(insert: .KSQL) { preview in
    let runway = try preview.load(airportID: "SQL", runway: "30")!
    preview.setTakeoff(runway: runway)
    let performance = TakeoffPerformanceViewModel(container: preview.container)
    performance.conditions = preview.veryHot

    return List {
      TakeoffDistanceView()
    }
    .environment(performance)
  }
}

#Preview("N/A") {
  PreviewView(insert: .KSQL) { preview in
    List {
      TakeoffDistanceView()
    }
    .environment(TakeoffPerformanceViewModel(container: preview.container))
  }
}
