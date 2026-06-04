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

  // MARK: - Elevation Reader

  /// Creates a snapshot of the currently loaded tiles for lock-free elevation queries.
  public func makeElevationReader() -> ElevationReader {
    ElevationReader(tiles: loadedTiles)
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
}

// MARK: - ElevationReader

/// A lightweight, `Sendable` snapshot of loaded terrain tiles for lock-free elevation queries.
///
/// Use ``TerrainService/makeElevationReader()`` to create an instance. Because this type
/// captures only immutable tile references, it can be passed freely across concurrency domains
/// without requiring actor hops for each query.
public struct ElevationReader: Sendable {
  private let tiles: [TerrainRegion: MappedTerrainTile]

  /// The set of terrain regions available in this snapshot.
  public let loadedRegions: Set<TerrainRegion>

  init(tiles: [TerrainRegion: MappedTerrainTile]) {
    self.tiles = tiles
    self.loadedRegions = Set(tiles.keys)
  }

  /// Returns the terrain elevation at a coordinate.
  public func elevation(at coordinate: CLLocationCoordinate2D) -> Measurement<UnitLength>? {
    elevation(at: coordinate.latitude, longitude: coordinate.longitude)
  }

  /// Returns the terrain elevation at a coordinate.
  public func elevation(at latitude: Double, longitude: Double) -> Measurement<UnitLength>? {
    let regions = TerrainRegion.containing(latitude: latitude, longitude: longitude)
    for region in regions {
      if let tile = tiles[region],
        let elevM = tile.interpolatedElevation(at: latitude, longitude: longitude)
      {
        return Measurement(value: elevM, unit: .meters)
      }
    }
    return nil
  }
}
