import SwiftUI
import WidgetKit

struct WidgetNoAirportView: View {
  @Environment(\.widgetFamily)
  var family

  private var font: Font {
    switch family {
      case .systemSmall: return .footnote
      default: return .subheadline
    }
  }

  var body: some View {
    Text("Select an airport from the SF50 TOLD app first.")
      .foregroundColor(.secondary)
      .font(font)
      .containerBackground(.background, for: .widget)
  }
}
