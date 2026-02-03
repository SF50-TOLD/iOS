import Foundation
import SF50_Shared

/// Progress state for terrain data processing.
///
/// Used by ``SRTMProcessor`` to report current processing stage. View models can poll
/// this state to update UI without callback complexity.
public enum TerrainProgress: Sendable {
  case pending

  /// Downloading tiles for a region.
  case downloading(region: TerrainRegion, completed: Int, total: Int)

  /// Parsing/combining downloaded tiles.
  case parsing(region: TerrainRegion, completed: Int, total: Int)

  /// Compressing region data (0.0-1.0).
  case compressing(region: TerrainRegion, fraction: Double)

  /// Writing manifest file.
  case generatingManifest

  /// Uploading region to R2 (fraction 0.0-1.0).
  case uploading(region: TerrainRegion, fraction: Double)

  /// Uploading manifest to R2.
  case uploadingManifest

  case completed
  case cancelled
  case failed(Error)

  /// Whether processing has finished (success, cancel, or failure).
  public var isFinished: Bool {
    switch self {
      case .completed, .cancelled, .failed: true
      default: false
    }
  }
}
