import SF50_Shared
import SwiftUI

/// The background of a downloaded-NOTAM card: plain, or set apart when the app can fill the NOTAM
/// in from it.
///
/// A card that can fill in is drawn with a thick border in ``IntelligenceGradient``, the gradient
/// washed faintly across its background, and a deeper, tinted shadow that lifts it further off the
/// page than a plain one. With Reduce Transparency on, the wash is left out.
struct NOTAMCardBackground: ViewModifier {

  // MARK: - Instance Properties

  /// Whether the app can fill the NOTAM in from this card.
  let isProposing: Bool

  @Environment(\.accessibilityReduceTransparency)
  private var reduceTransparency

  // MARK: - Instance Methods

  func body(content: Content) -> some View {
    content.background {
      if isProposing {
        ProposingCardBackground(isTinted: !reduceTransparency)
      } else {
        PlainCardBackground()
      }
    }
  }
}

/// The shape every card background is drawn in.
private let cardShape = RoundedRectangle(cornerRadius: 12)

/// A card the app can't fill the NOTAM in from: the system background, lifted slightly.
private struct PlainCardBackground: View {
  private static let shadowOpacity = 0.08,
    shadowRadius: CGFloat = 6,
    shadowOffset: CGFloat = 2

  var body: some View {
    cardShape
      .fill(Color(.systemBackground))
      .shadow(
        color: .black.opacity(Self.shadowOpacity),
        radius: Self.shadowRadius,
        y: Self.shadowOffset
      )
  }
}

/// A card the app can fill the NOTAM in from: the system background in a thick gradient border,
/// optionally washed faintly with the gradient, and lifted by a tinted shadow.
private struct ProposingCardBackground: View {
  private static let borderWidth: CGFloat = 2.5,
    lightTintOpacity = 0.08,
    darkTintOpacity = 0.16,
    shadowOpacity = 0.3,
    shadowRadius: CGFloat = 12,
    shadowOffset: CGFloat = 4

  let isTinted: Bool

  @Environment(\.colorScheme)
  private var colorScheme

  private var tintOpacity: Double {
    colorScheme == .dark ? Self.darkTintOpacity : Self.lightTintOpacity
  }

  var body: some View {
    cardShape
      .fill(Color(.systemBackground))
      .overlay {
        if isTinted { cardShape.fill(IntelligenceGradient.linear.opacity(tintOpacity)) }
      }
      .overlay { cardShape.strokeBorder(IntelligenceGradient.linear, lineWidth: Self.borderWidth) }
      .shadow(
        color: IntelligenceGradient.shadowColor.opacity(Self.shadowOpacity),
        radius: Self.shadowRadius,
        y: Self.shadowOffset
      )
  }
}

extension View {
  /// Draws a downloaded-NOTAM card's background, set apart when the app can fill the NOTAM in from
  /// it.
  func notamCardBackground(isProposing: Bool) -> some View {
    modifier(NOTAMCardBackground(isProposing: isProposing))
  }
}

#Preview {
  PreviewView { preview in
    let notam = preview.generateNOTAMs(count: 1, baseTime: .now)[0]
    return VStack(spacing: 24) {
      NOTAMListItemView(notam: notam, plannedTime: .now)
        .padding()
        .notamCardBackground(isProposing: false)
      NOTAMListItemView(notam: notam, plannedTime: .now, onFill: {})
        .padding()
        .notamCardBackground(isProposing: true)
    }
    .padding()
    .frame(maxHeight: .infinity)
    .background(Color(.systemGroupedBackground))
  }
}
