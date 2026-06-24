import SwiftUI
import WidgetKit

struct WidgetAirportView: View {
  var name: String?
  var body: some View {
    if let name {
      Text(name)
        .font(.headline)
    } else {
      Text("Airport Name").redacted(reason: .placeholder)
    }
  }
}
