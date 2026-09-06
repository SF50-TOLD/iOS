import SF50_Shared
import SwiftUI

/// Tells the pilot when iOS has reclaimed terrain they downloaded.
///
/// Asset packs are purgeable: the system deletes one when storage runs short and gives the app no
/// notice. Terrain is downloaded to be there in flight, so it going missing is worth interrupting
/// for — otherwise the region quietly reads as never downloaded and nobody finds out until the
/// profile has no terrain under it.
private struct TerrainPurgeAlert: ViewModifier {

  // MARK: - Instance Properties

  @ObservedObject private var loader = TerrainDataLoader.shared

  private var regionNames: [String] {
    loader.unannouncedPurgedRegions
      .map(\.displayName)
      .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
  }

  // MARK: - Other Methods

  func body(content: Content) -> some View {
    content
      .alert(
        Text("Terrain Data Removed"),
        isPresented: .init(
          get: { !loader.unannouncedPurgedRegions.isEmpty },
          set: { if !$0 { loader.acknowledgePurgedRegions() } }
        )
      ) {
        Button("OK") { loader.acknowledgePurgedRegions() }
      } message: {
        Text(
          "iOS removed the terrain data for \(regionNames, format: .list(type: .and)) to free up storage. Download it again from Settings to use terrain analysis there."
        )
      }
  }
}

extension View {

  /// Interrupts to say that iOS reclaimed downloaded terrain.
  func terrainPurgeAlert() -> some View {
    modifier(TerrainPurgeAlert())
  }
}
