import SwiftUI

/// A capsule filled with the deep ``IntelligenceGradient``, for actions that fill something in from
/// what the app read on its own. Its white title is at least 4.5:1 against every color in the fill.
struct IntelligenceButtonStyle: ButtonStyle {
  private static let verticalPadding: CGFloat = 8,
    pressedOpacity = 0.7

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .fontWeight(.semibold)
      .foregroundStyle(.white)
      .padding(.horizontal)
      .padding(.vertical, Self.verticalPadding)
      .background(IntelligenceGradient.deep, in: .capsule)
      .opacity(configuration.isPressed ? Self.pressedOpacity : 1)
  }
}

extension ButtonStyle where Self == IntelligenceButtonStyle {
  /// A capsule filled with the Apple Intelligence gradient.
  static var intelligence: Self { .init() }
}

#Preview {
  Button {
  } label: {
    Label("Auto-Fill", systemImage: "wand.and.sparkles")
  }
  .buttonStyle(.intelligence)
}
