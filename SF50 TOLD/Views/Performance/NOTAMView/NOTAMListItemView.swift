import SF50_Shared
import SwiftUI

struct NOTAMListItemView: View {
  let notam: NOTAMResponse
  let plannedTime: Date

  var body: some View {
    VStack(alignment: .leading) {
      // NOTAM ID and badges
      HStack {
        Text(notam.notamId)
          .font(.system(.subheadline, design: .monospaced).weight(.medium))
          .multilineTextAlignment(.leading)

        Spacer()

        NOTAMTimeBadge(notam: notam, plannedTime: plannedTime)
      }

      // NOTAM text - wrap instead of horizontal scroll
      Text(notam.notamText)
        .font(.system(.footnote, design: .monospaced))
        .fixedSize(horizontal: false, vertical: true)

      // Effective times
      VStack(alignment: .leading, spacing: 0) {
        Text("Effective: \(notam.effectiveStart, format: .dateTime)")
          .font(.caption)
          .foregroundStyle(.secondary)

        if let end = notam.effectiveEnd {
          Text("Until: \(end, format: .dateTime)")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
    }
  }
}

#Preview {
  PreviewView { preview in
    let now = Date()
    let notams = preview.generateNOTAMs(count: 5, icaoLocation: "NZNR", baseTime: now)

    return List {
      ForEach(notams) { notam in
        NOTAMListItemView(
          notam: notam,
          plannedTime: now
        )
      }
    }
  }
}
