import SwiftUI

/// The slanted gradient that marks what the app read from a NOTAM on its own, in the colors Apple
/// Intelligence uses for the same idea.
enum IntelligenceGradient {

  // MARK: - Type Properties

  private static let purple = Color(red: 0xBC / 255, green: 0x82 / 255, blue: 0xF3 / 255),
    pink = Color(red: 0xF5 / 255, green: 0xB9 / 255, blue: 0xEA / 255),
    periwinkle = Color(red: 0x8D / 255, green: 0x9F / 255, blue: 0xFF / 255),
    coral = Color(red: 0xFF / 255, green: 0x67 / 255, blue: 0x78 / 255),
    amber = Color(red: 0xFF / 255, green: 0xBA / 255, blue: 0x71 / 255)

  /// The same hues deepened until white text on each is at least 4.5:1, the WCAG AA contrast for
  /// body text; amber leans to orange, which stays recognizable where a deep amber turns brown.
  private static let deepPeriwinkle = Color(red: 0x46 / 255, green: 0x63 / 255, blue: 0xFF / 255),
    deepPurple = Color(red: 0x9C / 255, green: 0x46 / 255, blue: 0xED / 255),
    deepPink = Color(red: 0xD1 / 255, green: 0x1E / 255, blue: 0xB0 / 255),
    deepCoral = Color(red: 0xE9 / 255, green: 0x00 / 255, blue: 0x1A / 255),
    deepOrange = Color(red: 0xC4 / 255, green: 0x46 / 255, blue: 0x0A / 255)

  /// The colors, in order along the slant.
  static let colors = [periwinkle, purple, pink, coral, amber]

  /// The gradient, running from the top-leading corner to the bottom-trailing one.
  static let linear = LinearGradient(
    colors: colors,
    startPoint: .topLeading,
    endPoint: .bottomTrailing
  )

  /// The gradient in deep colors, for filling behind white text.
  static let deep = LinearGradient(
    colors: [deepPeriwinkle, deepPurple, deepPink, deepCoral, deepOrange],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
  )

  /// The color a shadow cast by something drawn in the gradient takes.
  static let shadowColor = purple
}

#Preview {
  RoundedRectangle(cornerRadius: 12)
    .fill(IntelligenceGradient.linear)
    .frame(width: 300, height: 120)
    .padding()
}
