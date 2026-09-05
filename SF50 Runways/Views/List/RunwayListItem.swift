import Defaults
import SF50_Shared
import SwiftUI
import WidgetKit

struct RunwayListItem: View {
  var runway: RunwaySnapshot
  var performance: RunwayPerformance?
  var conditions: Conditions?
  var operation: SF50_Shared.Operation

  @Default(.runwayLengthUnit)
  private var runwayLengthUnit

  private var availableDistance: Measurement<UnitLength> {
    runway.availableDistance(for: operation)
  }

  var body: some View {
    HStack {
      Text(runway.name).bold()
        .fixedSize(horizontal: true, vertical: false)

      if let conditions {
        WindComponents(runway: runway, conditions: conditions)
      }

      Spacer()

      switch performance?.distance {
        case .value(let measurement), .valueWithUncertainty(let measurement, _):
          Text(measurement.converted(to: runwayLengthUnit), format: .length)
            .foregroundColor(measurement > availableDistance ? .red : .green)
          Text("/")
          Text(availableDistance.converted(to: runwayLengthUnit), format: .length)
        case .offscaleHigh:
          Text("Exceeds Limits")
            .foregroundColor(.red)
            .bold()
        case .notAuthorized:
          Text("Config N/A")
            .foregroundColor(.red)
            .bold()
        case .invalid, .notAvailable, .offscaleLow:
          Text("N/A")
            .foregroundColor(.gray)
        case .none:
          Text("10,000′ / 10,000′")
            .redacted(reason: .placeholder)
      }
    }
  }
}
