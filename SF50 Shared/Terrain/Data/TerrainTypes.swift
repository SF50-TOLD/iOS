public import CoreLocation
public import Foundation

/// Errors that can occur during terrain queries.
public enum TerrainServiceError: LocalizedError {
  case regionNotLoaded(TerrainRegion)
  case noDataAtLocation(CLLocationCoordinate2D)
  case invalidFile(URL)
  case fileReadError(any Error)

  public var errorDescription: String? {
    String(localized: "Terrain data couldn’t be loaded.", bundle: .sharedFramework)
  }

  public var failureReason: String? {
    switch self {
      case .regionNotLoaded(let region):
        String(
          localized: "Terrain data for \(region.displayName) is not loaded.",
          bundle: .sharedFramework
        )
      case .noDataAtLocation(let coord):
        String(
          localized:
            "No terrain data available at \(coord.latitude, format: .number), \(coord.longitude, format: .number).",
          bundle: .sharedFramework
        )
      case .invalidFile(let url):
        String(
          localized: "The terrain file “\(url.lastPathComponent)” is invalid or corrupted.",
          bundle: .sharedFramework
        )
      case .fileReadError(let error):
        String(
          localized: "Failed to read terrain file: \(error.localizedDescription)",
          bundle: .sharedFramework
        )
    }
  }

  public var recoverySuggestion: String? {
    switch self {
      case .regionNotLoaded:
        String(
          localized: "Download terrain data for this region in Settings.",
          bundle: .sharedFramework
        )
      case .noDataAtLocation:
        nil
      case .invalidFile, .fileReadError:
        String(
          localized: "Try re-downloading terrain data for this region.",
          bundle: .sharedFramework
        )
    }
  }
}
