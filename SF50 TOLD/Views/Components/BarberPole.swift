import SwiftUI

/// Diagonal red stripes on gray, after the airspeed indicator's mark for where the aircraft must not
/// be, used here for altitudes the climb charts do not cover.
///
/// Muted, so a band across the top of the chart doesn't outshout the path and terrain beneath it.
struct BarberPole: View {

  /// How wide each stripe is drawn, measured across the stripe.
  private static let stripeWidthPts: CGFloat = 4

  /// How much of the stripes' red is gray.
  private static let stripeGrayFraction = 0.35

  private static let groundColor = Color(.systemGray5),
    stripeColor = Color(.systemRed).mix(with: Color(.systemGray), by: stripeGrayFraction)

  var body: some View {
    Canvas { context, size in
      context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Self.groundColor))
      context.fill(stripes(in: size), with: .color(Self.stripeColor))
    }
  }

  /// The red stripes, running up to the right at 45° and spaced a stripe apart.
  private func stripes(in size: CGSize) -> Path {
    let width = Self.stripeWidthPts * 2.squareRoot()
    return Path { path in
      for left in stride(from: -size.height, to: size.width, by: width * 2) {
        path.addLines([
          .init(x: left, y: size.height),
          .init(x: left + width, y: size.height),
          .init(x: left + width + size.height, y: 0),
          .init(x: left + size.height, y: 0)
        ])
        path.closeSubpath()
      }
    }
  }
}

/// The legend entry for altitudes the AFM publishes no climb data for.
struct OutsideChartsKey: View {

  private static let swatchWidthPts: CGFloat = 22,
    swatchHeightPts: CGFloat = 10

  var body: some View {
    HStack(spacing: 6) {
      BarberPole()
        .frame(width: Self.swatchWidthPts, height: Self.swatchHeightPts)
        .clipShape(.rect(cornerRadius: 2))
        .accessibilityHidden(true)
      Text("Outside published AFM data")
    }
    .font(.caption2)
    .foregroundStyle(Color.secondary)
  }
}

#Preview("Barber pole") {
  VStack(alignment: .leading, spacing: 16) {
    BarberPole().frame(height: 60)
    OutsideChartsKey()
  }
  .padding()
}
