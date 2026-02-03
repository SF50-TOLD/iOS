import SwiftUI

/// Placeholder for terrain-based climb gradient analysis.
struct TerrainClimbAnalysisView: View {
  var body: some View {
    ContentUnavailableView(
      "Terrain Analysis",
      systemImage: "mountain.2",
      description: Text("Terrain climb analysis is not yet available.")
    )
  }
}

#Preview {
  TerrainClimbAnalysisView()
}
