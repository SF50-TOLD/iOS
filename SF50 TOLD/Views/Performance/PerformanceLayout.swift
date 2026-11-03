import SF50_Shared
import SwiftUI

/// Lays out a performance screen's inputs and results: as two forms at regular width, and as one
/// form, inputs first, at compact width.
///
/// At regular width the inputs and results sit side by side, or stacked where the space is
/// taller than wide, so the results stay in view while an input is changed. On iPhone Duo's inner
/// display the split follows the fold.
struct PerformanceLayout<Inputs: View, Results: View>: View {
  /// The share of the height the inputs take when the forms are stacked, enough for every input
  /// on a 13-inch iPad in portrait while iPhone Duo's inner display still shows every result.
  private static var stackedInputsShare: CGFloat { 0.62 }

  @Environment(\.horizontalSizeClass)
  private var horizontalSizeClass

  @ViewBuilder let inputs: () -> Inputs
  @ViewBuilder let results: () -> Results

  var body: some View {
    if #available(iOS 27.1, *), horizontalSizeClass == .regular {
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
      .splitArrangementLayoutRatio(idealVertical: Self.stackedInputsShare)
    } else {
      Form {
        inputs()
        results()
      }
    }
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
