import SwiftUI

/// A pill-shaped background modifier that wraps content in a capsule.
struct PillModifier<S: ShapeStyle>: ViewModifier {
  let fill: S

  func body(content: Content) -> some View {
    content
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background(
        Capsule()
          .fill(fill)
      )
  }
}

extension View {
  /// Applies a pill-shaped background to the view.
  func pill<S: ShapeStyle>(fill: S) -> some View {
    modifier(PillModifier(fill: fill))
  }
}
