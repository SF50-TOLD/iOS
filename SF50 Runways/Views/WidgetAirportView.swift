import Defaults
import SF50_Shared
import SwiftUI
import WidgetKit

struct WidgetAirportView: View {
  var name: String?
  var operation: SF50_Shared.Operation = .takeoff
  var VREF: Value<Measurement<UnitSpeed>>?

  @Default(.speedUnit)
  private var speedUnit

  var body: some View {
    HStack(alignment: .firstTextBaseline) {
      if let name {
        Text(name)
          .font(.headline)
          .lineLimit(1)
      } else {
        Text("Airport Name").redacted(reason: .placeholder)
      }

      Spacer()

      if operation == .landing { landingSummary }
    }
  }

  /// VREF depends on weight, flaps and conditions but not on the runway, so it belongs beside the
  /// airport rather than repeated on every row.
  @ViewBuilder private var landingSummary: some View {
    if let speed = VREF?.nominal {
      Text("VREF \(speed.converted(to: speedUnit), format: .speed)")
        .font(.caption)
        .foregroundStyle(.secondary)
    } else {
      Text("Landing")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }
}
