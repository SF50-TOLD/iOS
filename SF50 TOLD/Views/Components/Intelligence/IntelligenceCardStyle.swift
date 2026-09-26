import Defaults
import SF50_Shared
import SwiftUI

/// How a card the app can fill a NOTAM in from is set apart from the others.
///
/// Every style draws a thick border in ``IntelligenceGradient`` and lifts the card further off the
/// page than a plain one; they differ in how much of the gradient reaches the card itself. With
/// Reduce Transparency on, every style draws as ``border``.
enum IntelligenceCardStyle: String, CaseIterable, Identifiable, Defaults.Serializable {
  /// The gradient border and a deeper, tinted shadow.
  case border
  /// The border, with the gradient washed faintly across the card's background.
  case tinted
  /// The tinted card, glowing with the gradient in place of a shadow.
  case glow

  var id: Self { self }

  var title: LocalizedStringResource {
    switch self {
      case .border: "Border"
      case .tinted: "Tinted"
      case .glow: "Glow"
    }
  }
}

/// The background of a downloaded-NOTAM card: plain, or in an ``IntelligenceCardStyle`` when the
/// app can fill the NOTAM in from it.
struct NOTAMCardBackground: ViewModifier {

  // MARK: - Instance Properties

  /// Whether the app can fill the NOTAM in from this card.
  let isProposing: Bool

  /// The style to draw in, overriding the one chosen in Settings; for previews.
  var styleOverride: IntelligenceCardStyle?

  @Default(.intelligenceCardStyle)
  private var chosenStyle

  @Environment(\.accessibilityReduceTransparency)
  private var reduceTransparency

  private var style: IntelligenceCardStyle {
    reduceTransparency ? .border : styleOverride ?? chosenStyle
  }

  // MARK: - Instance Methods

  func body(content: Content) -> some View {
    content.background {
      if isProposing { ProposingCardBackground(style: style) } else { PlainCardBackground() }
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

/// A card the app can fill the NOTAM in from, in `style`.
private struct ProposingCardBackground: View {
  private static let shadowOpacity = 0.3,
    shadowRadius: CGFloat = 12,
    shadowOffset: CGFloat = 4,
    glowRadius: CGFloat = 14,
    glowOpacity = 0.8

  let style: IntelligenceCardStyle

  var body: some View {
    switch style {
      case .border:
        GradientBorderedCard(isTinted: false).shadow(
          color: IntelligenceGradient.shadowColor.opacity(Self.shadowOpacity),
          radius: Self.shadowRadius,
          y: Self.shadowOffset
        )
      case .tinted:
        GradientBorderedCard(isTinted: true).shadow(
          color: IntelligenceGradient.shadowColor.opacity(Self.shadowOpacity),
          radius: Self.shadowRadius,
          y: Self.shadowOffset
        )
      case .glow:
        GradientBorderedCard(isTinted: true)
          .background {
            cardShape
              .fill(IntelligenceGradient.linear)
              .blur(radius: Self.glowRadius)
              .opacity(Self.glowOpacity)
          }
    }
  }
}

/// The system background in a thick ``IntelligenceGradient`` border, optionally washed faintly with
/// the gradient.
private struct GradientBorderedCard: View {
  private static let borderWidth: CGFloat = 2.5,
    lightTintOpacity = 0.08,
    darkTintOpacity = 0.16

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
  }
}

extension View {
  /// Draws a downloaded-NOTAM card's background, set apart when the app can fill the NOTAM in from
  /// it.
  func notamCardBackground(
    isProposing: Bool,
    style: IntelligenceCardStyle? = nil
  ) -> some View {
    modifier(NOTAMCardBackground(isProposing: isProposing, styleOverride: style))
  }
}

extension Defaults.Keys {
  /// The ``IntelligenceCardStyle`` proposing NOTAM cards are drawn in.
  static let intelligenceCardStyle = Key<IntelligenceCardStyle>(
    "SF50/3/intelligenceCardStyle",
    default: .tinted
  )
}

#Preview("Styles") {
  PreviewView { preview in
    let notam = preview.generateNOTAMs(count: 1, baseTime: .now)[0]
    return ScrollView {
      VStack(spacing: 24) {
        NOTAMListItemView(notam: notam, plannedTime: .now)
          .padding()
          .notamCardBackground(isProposing: false)
        ForEach(IntelligenceCardStyle.allCases) { style in
          NOTAMListItemView(notam: notam, plannedTime: .now, onFill: {})
            .padding()
            .notamCardBackground(isProposing: true, style: style)
        }
      }
      .padding()
    }
    .background(Color(.systemGroupedBackground))
  }
}
