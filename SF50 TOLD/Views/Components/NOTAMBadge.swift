import SF50_Shared
import SwiftUI

/// Badge showing configured vs available NOTAM counts.
///
/// Displays NOTAM status with color coding:
/// - Gray: No NOTAMs available
/// - Orange: Available NOTAMs not configured
/// - Green: All available NOTAMs configured
struct NOTAMBadge: View {
  /// The gap between the badge's items, wider than the gap within one so each count stays with its
  /// icon.
  private static let itemSpacing: CGFloat = 12

  /// Number of NOTAMs configured/applied in the app
  let localCount: Int

  /// Number of NOTAMs available from the API
  let downloadedCount: Int

  /// Whether NOTAMs are currently being loaded
  let isLoading: Bool

  /// Whether a NOTAM fetch has been attempted (to distinguish "not fetched" from "fetched with 0")
  let hasAttemptedFetch: Bool

  /// Whether a downloaded NOTAM can fill in the NOTAM editor.
  let canFill: Bool

  var body: some View {
    HStack(spacing: Self.itemSpacing) {
      if isLoading {
        HStack {
          ProgressView()
            .controlSize(.mini)
          Text("Loading…")
        }
      } else {
        if canFill {
          Image(systemName: "wand.and.sparkles")
            .foregroundStyle(IntelligenceGradient.linear)
            .accessibilityLabel("Can fill in from downloaded NOTAMs")
        }
        Label {
          Text("\(localCount, format: .number)")
            .contentTransition(.numericText())
            .animation(.default, value: localCount)
        } icon: {
          Image(systemName: "pencil")
            .accessibilityLabel("Configured NOTAMs")
        }

        // Only show download count if we've attempted to fetch
        if hasAttemptedFetch {
          Label {
            Text("\(downloadedCount, format: .number)")
              .contentTransition(.numericText())
              .animation(.default, value: downloadedCount)
          } icon: {
            Image(systemName: "network")
              .accessibilityLabel("Downloaded NOTAMs")
          }
        }
      }
    }
    .labelStyle(CountLabelStyle())
    .font(.caption2)
    .fontWeight(.medium)
    .foregroundStyle(textColor)
    .pill(fill: Color.secondary.opacity(0.1))
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibilityLabel)
  }

  private var textColor: Color {
    if isLoading {
      return .secondary
    }
    // If we haven't fetched yet, just show based on configured count
    if !hasAttemptedFetch {
      return localCount > 0 ? .primary : .secondary
    }
    // If we have fetched, show based on both counts
    if localCount == 0 || downloadedCount == 0 {
      return .secondary
    }
    return .primary
  }

  private var accessibilityLabel: String {
    guard canFill else { return countsAccessibilityLabel }
    return String(localized: "\(countsAccessibilityLabel), can fill in from downloaded NOTAMs")
  }

  private var countsAccessibilityLabel: String {
    if isLoading {
      if localCount > 0 {
        return String(
          localized: "\(localCount, format: .count) configured, loading NOTAMs"
        )
      }
      return String(localized: "Loading NOTAMs")
    }
    if hasAttemptedFetch {
      return String(
        localized:
          "\(localCount, format: .count) configured, \(downloadedCount, format: .count) downloaded"
      )
    }
    return String(localized: "\(localCount, format: .count) configured")
  }

  init(
    configuredCount: Int,
    availableCount: Int,
    isLoading: Bool = false,
    hasAttemptedFetch: Bool = false,
    canFill: Bool = false
  ) {
    self.localCount = configuredCount
    self.downloadedCount = availableCount
    self.isLoading = isLoading
    self.hasAttemptedFetch = hasAttemptedFetch
    self.canFill = canFill
  }
}

/// A count with its icon, set close together so the pair reads as one item among the badge's
/// others.
private struct CountLabelStyle: LabelStyle {
  private static let spacing: CGFloat = 2

  func makeBody(configuration: LabelStyleConfiguration) -> some View {
    HStack(spacing: Self.spacing) {
      configuration.icon
      configuration.title
    }
  }
}

#Preview {
  List {
    LabeledContent("Loading") {
      NOTAMBadge(configuredCount: 0, availableCount: 0, isLoading: true)
    }
    LabeledContent("None") {
      NOTAMBadge(configuredCount: 0, availableCount: 0)
    }
    LabeledContent("Some") {
      NOTAMBadge(configuredCount: 2, availableCount: 5)
    }
    LabeledContent("Can Fill") {
      NOTAMBadge(configuredCount: 0, availableCount: 5, hasAttemptedFetch: true, canFill: true)
    }
  }
}
