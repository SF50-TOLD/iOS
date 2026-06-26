import SwiftUI

/// Indicates that the terrain path is being computed.
///
/// Renders an indeterminate ``ProgressView`` in normal use. Under UI testing it
/// degrades to a static label, because an indeterminate spinner is a perpetual
/// animation that keeps the app from going idle — stalling the test harness's
/// wait-for-idle against a background computation the tests don't assert on.
struct TerrainComputingIndicator: View {
  var body: some View {
    if UITestingHelper.isUITesting {
      Text("Computing terrain path…")
        .foregroundStyle(.secondary)
    } else {
      ProgressView("Computing terrain path…")
    }
  }
}

#Preview {
  TerrainComputingIndicator()
}
