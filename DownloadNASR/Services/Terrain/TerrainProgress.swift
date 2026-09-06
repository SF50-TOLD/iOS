import Foundation
import SF50_Shared

/// Progress state for terrain data processing.
///
/// Used by ``SRTMProcessor`` to report current processing stage. View models can poll
/// this state to update UI without callback complexity.
enum TerrainProgress: Sendable {
  case pending

  /// Downloading tiles for a region.
  case downloading(region: TerrainRegion, completed: Int, total: Int)

  /// Parsing/combining downloaded tiles.
  case parsing(region: TerrainRegion, completed: Int, total: Int)

  /// Writing manifest file.
  case generatingManifest

  /// Packaging a region's payload into an asset-pack archive.
  case packaging(region: TerrainRegion)

  /// Uploading region to R2 (fraction 0.0-1.0).
  case uploading(region: TerrainRegion, fraction: Double)

  /// Uploading manifest to R2.
  case uploadingManifest

  case completed
  case cancelled
  case failed(any Error)
}
