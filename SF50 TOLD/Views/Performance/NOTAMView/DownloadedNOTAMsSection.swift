import SF50_Shared
import SwiftUI

/// The downloaded NOTAMs, as a carousel of cards. Cards the app can fill the NOTAM editor in from
/// are set apart and carry a button that does so; cards that likely affect runway performance are
/// set apart in red.
struct DownloadedNOTAMsSection: View {
  /// Room around each card for its shadow or glow, which the carousel would otherwise clip.
  private static let cardMargin: CGFloat = 20

  /// The NOTAMs, in the order to show them.
  let notams: [NOTAMResponse]
  let plannedTime: Date

  /// Where a NOTAM sits in the list, which sets how its card is drawn.
  let tier: (NOTAMResponse) -> NOTAMResponse.ListTier

  /// Fills the NOTAM editor in from a NOTAM.
  let onFill: (NOTAMResponse) -> Void

  /// The carousel's height, which grows with the text size so a card's text isn't cut off.
  @ScaledMetric(relativeTo: .footnote)
  private var carouselHeight: CGFloat = 300

  @State private var currentIndex = 0

  var body: some View {
    Section {
      VStack(spacing: 0) {
        CarouselView(
          data: notams,
          id: \.id,
          content: { notam in
            let tier = tier(notam)
            NOTAMListItemView(
              notam: notam,
              plannedTime: plannedTime,
              mayAffectPerformance: tier == .relevant,
              onFill: tier == .fillable ? { onFill(notam) } : nil
            )
            .padding()
            .notamCardBackground(for: tier)
            .padding(Self.cardMargin)
          },
          currentIndex: $currentIndex
        )
        .frame(height: carouselHeight)

        CarouselIndicator(currentIndex: $currentIndex, totalPages: notams.count)
      }
      .listRowBackground(Color.clear)
      // The margin around each card stands in for the row’s own insets.
      .listRowInsets(.init())
    } header: {
      Text(
        "Downloaded NOTAMs (\(currentIndex + 1, format: .number) of \(notams.count, format: .number))"
      )
    }
  }
}

#Preview {
  PreviewView { preview in
    let notams = NOTAMResponse.readableSamples() + preview.generateNOTAMs(count: 3)
    return Form {
      DownloadedNOTAMsSection(
        notams: notams,
        plannedTime: .now,
        tier: { $0.listTier(at: .now, canFill: $0.notamText.contains("FICON")) },
        onFill: { _ in }
      )
    }
  }
}
