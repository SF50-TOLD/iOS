import CoreLocation
import Foundation

/// A point along a terrain profile with elevation data.
public struct TerrainProfilePoint: Sendable, Equatable {
  /// Distance from the start of the profile in nautical miles.
  public let distanceNM: Double

  /// Coordinate of this point.
  public let coordinate: CLLocationCoordinate2D

  /// Terrain elevation at this point in meters.
  public let elevationM: Double

  /// Terrain elevation at this point.
  public var elevation: Measurement<UnitLength> {
    Measurement(value: elevationM, unit: .meters)
  }

  public init(
    distanceNM: Double,
    coordinate: CLLocationCoordinate2D,
    elevationM: Double
  ) {
    self.distanceNM = distanceNM
    self.coordinate = coordinate
    self.elevationM = elevationM
  }

  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.distanceNM == rhs.distanceNM
      && lhs.coordinate.latitude == rhs.coordinate.latitude
      && lhs.coordinate.longitude == rhs.coordinate.longitude
      && lhs.elevationM == rhs.elevationM
  }
}

/// A terrain elevation profile along a route.
public struct TerrainProfile: Sendable {
  /// Points along the profile.
  public let points: [TerrainProfilePoint]

  /// Total distance of the profile in nautical miles.
  public var totalDistanceNM: Double {
    points.last?.distanceNM ?? 0
  }

  /// Maximum terrain elevation along the profile.
  public var maxElevation: Measurement<UnitLength>? {
    points.max(by: { $0.elevation < $1.elevation })?.elevation
  }

  /// Minimum terrain elevation along the profile.
  public var minElevation: Measurement<UnitLength>? {
    points.min(by: { $0.elevation < $1.elevation })?.elevation
  }

  public init(points: [TerrainProfilePoint]) {
    self.points = points
  }
}

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
