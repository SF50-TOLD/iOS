import SF50_Shared
import SwiftUI

/// Lays out a performance screen's inputs and results: as two forms side by side at regular width
/// in a space wider than tall, and otherwise as one form, inputs first.
///
/// Side by side, the results stay in view while an input is changed. On iPhone Duo's inner display
/// the split follows the fold.
struct PerformanceLayout<Inputs: View, Results: View>: View {
  @Environment(\.horizontalSizeClass)
  private var horizontalSizeClass

  @State private var measuredWidth: CGFloat?
  @State private var isWiderThanTall = false

  @ViewBuilder let inputs: () -> Inputs
  @ViewBuilder let results: () -> Results

  private var canSplit: Bool { horizontalSizeClass == .regular && isWiderThanTall }

  var body: some View {
    Group {
      if #available(iOS 27.1, *), canSplit {
        ArrangementView {
          Form { inputs() }
            .accessibilityIdentifier("performanceInputs")
            .modifier(SeamMargin(edge: .trailing))
        } secondary: {
          Form { results() }
            .accessibilityIdentifier("performanceResults")
            .modifier(SeamMargin(edge: .leading))
        }
        .arrangementViewStyle(.split)
      } else {
        Form {
          inputs()
          results()
        }
      }
    }
    .onGeometryChange(for: CGSize.self, of: \.size, action: measureShape)
  }

  /// Takes the space's shape when its width changes, which a rotation, an unfold or a window resize
  /// does and the software keyboard, taking only height, does not.
  private func measureShape(_ size: CGSize) {
    guard size.width != measuredWidth else { return }
    measuredWidth = size.width
    isWiderThanTall = size.width > size.height
  }
}

/// Keeps a pane's sections off the seam when the panes sit side by side, where a form's own
/// margins don't separate it from its neighbour.
@available(iOS 27.1, *)
private struct SeamMargin: ViewModifier {
  private static let marginPt: CGFloat = 10

  let edge: Edge

  @Environment(\.splitArrangementAxis)
  private var splitAxis

  func body(content: Content) -> some View {
    content.safeAreaPadding(Edge.Set(edge), splitAxis == .horizontal ? Self.marginPt : 0)
  }
}

#Preview("Compact") {
  PreviewView(insert: .KOAK) { preview in
    let runway = try preview.load(airportID: "OAK", runway: "28R")!
    preview.setTakeoff(runway: runway)

    return TakeoffView()
      .environment(\.horizontalSizeClass, .compact)
  }
}

#Preview("Regular") {
  PreviewView(insert: .KOAK) { preview in
    let runway = try preview.load(airportID: "OAK", runway: "28R")!
    preview.setTakeoff(runway: runway)

    return TakeoffView()
      .environment(\.horizontalSizeClass, .regular)
  }
}
