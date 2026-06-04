import CoreLocation
import Foundation

/// Errors that can occur during terrain queries.
public enum TerrainServiceError: LocalizedError {
  case regionNotLoaded(TerrainRegion)
  case noDataAtLocation(CLLocationCoordinate2D)
  case invalidFile(URL)
  case fileReadError(Error)

  public var errorDescription: String? {
    String(localized: "Terrain data couldn’t be loaded.")
  }

  public var failureReason: String? {
    switch self {
      case .regionNotLoaded(let region):
        String(localized: "Terrain data for \(region.displayName) is not loaded.")
      case .noDataAtLocation(let coord):
        String(
          localized:
            "No terrain data available at \(coord.latitude, format: .number), \(coord.longitude, format: .number)."
        )
      case .invalidFile(let url):
        String(localized: "The terrain file “\(url.lastPathComponent)” is invalid or corrupted.")
      case .fileReadError(let error):
        String(localized: "Failed to read terrain file: \(error.localizedDescription)")
    }
  }

  public var recoverySuggestion: String? {
    switch self {
      case .regionNotLoaded:
        String(localized: "Download terrain data for this region in Settings.")
      case .noDataAtLocation:
        nil
      case .invalidFile, .fileReadError:
        String(localized: "Try re-downloading terrain data for this region.")
    }
  }
}
