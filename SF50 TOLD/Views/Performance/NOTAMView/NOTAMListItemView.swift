import SF50_Shared
import SwiftUI

struct NOTAMListItemView: View {
  /// Room above and below the effective times, which set them apart from the text and the button.
  private static let datesPadding: CGFloat = 4

  let notam: NOTAMResponse
  let plannedTime: Date

  /// Whether the NOTAM is marked as likely to affect runway performance, which VoiceOver announces.
  var mayAffectPerformance = false

  /// Fills the NOTAM editor in from this NOTAM; `nil` when the app read nothing it can fill in.
  var onFill: (() -> Void)?

  private var identifierAccessibilityLabel: Text {
    mayAffectPerformance
      ? Text("\(notam.notamId), may affect runway performance")
      : Text(notam.notamId)
  }

  var body: some View {
    VStack(alignment: .leading) {
      // NOTAM ID and badges
      HStack {
        Text(notam.notamId)
          .font(.system(.subheadline, design: .monospaced).weight(.medium))
          .multilineTextAlignment(.leading)
          .accessibilityLabel(identifierAccessibilityLabel)

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
      .padding(.vertical, Self.datesPadding)

      if let onFill {
        Button(action: onFill) {
          Label("Auto-Fill", systemImage: "wand.and.sparkles")
        }
        .buttonStyle(.intelligence)
        .accessibilityHint("Fills in this runway’s NOTAM entries from this NOTAM")
        .accessibilityIdentifier("fillFromNOTAMButton")
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
          plannedTime: now,
          onFill: notam.id.isMultiple(of: 2) ? {} : nil
        )
      }
    }
  }
}
