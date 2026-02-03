import CoreLocation
import Foundation
import os

/// Service for querying terrain elevation data.
///
/// ``TerrainService`` provides the main API for terrain elevation queries:
/// - Point elevation lookups
/// - Route profile generation
///
/// ## Usage
///
/// ```swift
/// let service = TerrainService()
///
/// // Load terrain data for a region
/// try service.loadRegion(.northAmerica, from: terrainFileURL)
///
/// // Query elevation at a point
/// if let elevation = service.elevation(at: coordinate) {
///     print("Elevation: \(elevation.converted(to: .feet))")
/// }
///
/// // Generate elevation profile along a route
/// let profile = service.profile(along: routeCoordinates, sampleIntervalNM: 0.5)
/// ```
public actor TerrainService {

  // MARK: - Type Properties

  /// Shared instance of the terrain service.
  public static let shared = TerrainService()

  // MARK: - Instance Properties

  /// Loaded terrain tiles by region.
  private var loadedTiles: [TerrainRegion: MappedTerrainTile] = [:]

  /// Logger for debug output.
  private let logger = Logger(
    subsystem: "codes.tim.SF50-TOLD",
    category: "TerrainService"
  )

  /// Returns all loaded regions.
  public var loadedRegions: Set<TerrainRegion> {
    Set(loadedTiles.keys)
  }

  // MARK: - Initializers

  public init() {}

  // MARK: - Loading

  /// Loads terrain data for a region from a file.
  /// - Parameters:
  ///   - region: The region to load
  ///   - fileURL: URL to the terrain data file
  public func loadRegion(_ region: TerrainRegion, from fileURL: URL) throws {
    logger.info("Loading terrain for \(region.displayName) from \(fileURL.path)")

    let tile = try MappedTerrainTile(fileURL: fileURL)
    loadedTiles[region] = tile

    logger.info(
      "Loaded \(region.displayName): \(tile.tileCount) tiles, resolution \(tile.resolution)"
    )
  }

  /// Unloads terrain data for a region to free memory.
  public func unloadRegion(_ region: TerrainRegion) {
    loadedTiles.removeValue(forKey: region)
    logger.info("Unloaded terrain for \(region.displayName)")
  }

  /// Checks if a region's terrain data is loaded.
  public func isRegionLoaded(_ region: TerrainRegion) -> Bool {
    loadedTiles[region] != nil
  }

  // MARK: - Point Elevation

  /// Returns the terrain elevation at a coordinate.
  /// - Parameter coordinate: The coordinate to query
  /// - Returns: Elevation as a measurement, or nil if no data available
  public func elevation(at coordinate: CLLocationCoordinate2D) -> Measurement<UnitLength>? {
    elevationM(at: coordinate).map { Measurement(value: $0, unit: .meters) }
  }

  /// Returns the terrain elevation at a coordinate.
  /// - Parameters:
  ///   - latitude: Latitude in decimal degrees
  ///   - longitude: Longitude in decimal degrees
  /// - Returns: Elevation as a measurement, or nil if no data available
  public func elevation(at latitude: Double, longitude: Double) -> Measurement<UnitLength>? {
    elevationM(at: latitude, longitude: longitude).map { Measurement(value: $0, unit: .meters) }
  }

  /// Returns the terrain elevation in meters at a coordinate.
  /// - Parameter coordinate: The coordinate to query
  /// - Returns: Elevation in meters, or nil if no data available
  func elevationM(at coordinate: CLLocationCoordinate2D) -> Double? {
    elevationM(at: coordinate.latitude, longitude: coordinate.longitude)
  }

  /// Returns the terrain elevation in meters at a coordinate.
  /// - Parameters:
  ///   - latitude: Latitude in decimal degrees
  ///   - longitude: Longitude in decimal degrees
  /// - Returns: Elevation in meters, or nil if no data available
  func elevationM(at latitude: Double, longitude: Double) -> Double? {
    let regions = TerrainRegion.containing(latitude: latitude, longitude: longitude)
    for region in regions {
      if let tile = loadedTiles[region] {
        return tile.interpolatedElevation(at: latitude, longitude: longitude)
      }
    }
    return nil
  }

  // MARK: - Route Profile

  /// Generates an elevation profile along a route.
  /// - Parameters:
  ///   - coordinates: Array of coordinates defining the route
  ///   - sampleIntervalNM: Distance between elevation samples in nautical miles
  /// - Returns: Terrain profile with elevation points along the route
  public func profile(
    along coordinates: [CLLocationCoordinate2D],
    sampleIntervalNM: Double = 0.5
  ) -> TerrainProfile {
    guard coordinates.count >= 2 else {
      return TerrainProfile(points: [])
    }

    var points: [TerrainProfilePoint] = []
    var totalDistanceNM = 0.0

    // Add first point
    if let elevM = elevationM(at: coordinates[0]) {
      points.append(
        .init(
          distanceNM: 0,
          coordinate: coordinates[0],
          elevationM: elevM
        )
      )
    }

    // Process each segment
    for i in 1..<coordinates.count {
      let from = coordinates[i - 1]
      let to = coordinates[i]
      let segmentDistanceNM = GeoCalculations.distanceNM(from: from, to: to)

      // Sample points along the segment
      var segmentOffset = sampleIntervalNM
      while segmentOffset < segmentDistanceNM {
        let fraction = segmentOffset / segmentDistanceNM
        let intermediate = GeoCalculations.interpolate(from: from, to: to, fraction: fraction)

        if let elevM = elevationM(at: intermediate) {
          points.append(
            .init(
              distanceNM: totalDistanceNM + segmentOffset,
              coordinate: intermediate,
              elevationM: elevM
            )
          )
        }

        segmentOffset += sampleIntervalNM
      }

      // Add endpoint
      totalDistanceNM += segmentDistanceNM
      if let elevM = elevationM(at: to) {
        points.append(
          .init(
            distanceNM: totalDistanceNM,
            coordinate: to,
            elevationM: elevM
          )
        )
      }
    }

    return TerrainProfile(points: points)
  }
}
