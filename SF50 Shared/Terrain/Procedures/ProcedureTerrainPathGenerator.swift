import CoreLocation
import Foundation
import NavData
import os
public import SwiftData

/// Generates a ``ProcedureTerrainPath`` by combining a ``ProcedurePath`` with
/// terrain elevation and obstacle data within a lateral corridor.
public struct ProcedureTerrainPathGenerator {

  /// SwiftData container for fetching obstacles.
  private let modelContainer: ModelContainer

  /// Total lateral corridor width in nautical miles.
  public let corridorWidthNM: Double

  /// Service for querying terrain elevation data.
  private let terrainService: TerrainService

  /// Emits the intervals that put generation on an Instruments timeline.
  private let signposter = OSSignposter(
    subsystem: "codes.tim.SF50-TOLD",
    category: "ProcedureTerrainPathGenerator"
  )

  public init(
    modelContainer: ModelContainer,
    corridorWidthNM: Double = 0.25,
    terrainService: TerrainService = .shared
  ) {
    self.modelContainer = modelContainer
    self.corridorWidthNM = corridorWidthNM
    self.terrainService = terrainService
  }

  // MARK: - Helpers

  /// Finds the index of the path point nearest to a given cumulative distance.
  private static func nearestPointIndex(
    atDistanceNM target: Double,
    in points: [ProcedurePath.Point]
  ) -> Int {
    var bestIndex = 0,
      bestDelta = abs(points[0].distanceNM - target)

    for i in 1..<points.count {
      let delta = abs(points[i].distanceNM - target)
      if delta < bestDelta {
        bestDelta = delta
        bestIndex = i
      } else {
        // Points are sorted by distance, so once delta increases we're past the closest
        break
      }
    }

    return bestIndex
  }

  /// Computes the path bearing at a given point index using neighboring points.
  private static func pathBearing(
    at index: Int,
    in points: [ProcedurePath.Point]
  ) -> Measurement<UnitAngle> {
    let from: CLLocationCoordinate2D,
      to: CLLocationCoordinate2D

    if points.count == 1 {
      return .init(value: 0, unit: .degrees)
    }
    if index == 0 {
      from = points[0].coordinate
      to = points[1].coordinate
    } else if index == points.count - 1 {
      from = points[index - 1].coordinate
      to = points[index].coordinate
    } else {
      from = points[index - 1].coordinate
      to = points[index + 1].coordinate
    }

    return GeoCalculations.bearing(from: from, to: to)
  }

  // MARK: - Public API

  /// Generates a terrain-enriched path from a procedure path.
  ///
  /// - Parameter path: The procedure path providing aircraft positions and altitudes.
  /// - Returns: A ``ProcedureTerrainPath`` with terrain and obstacle data per point.
  public func generate(from path: ProcedurePath) async -> ProcedureTerrainPath {
    let interval = signposter.beginInterval(
      "generate procedure terrain path",
      id: signposter.makeSignpostID()
    )
    defer { signposter.endInterval("generate procedure terrain path", interval) }

    let pathPoints = path.points
    guard !pathPoints.isEmpty else {
      return ProcedureTerrainPath(corridorWidthNM: corridorWidthNM, points: [])
    }

    let reader = await terrainService.makeElevationReader()

    let obstacleData = fetchObstacles(pathPoints: pathPoints)
    let obstaclesByIndex = assignObstaclesToPoints(
      obstacles: obstacleData,
      pathPoints: pathPoints
    )

    let halfCorridorNM = corridorWidthNM / 2,
      quarterCorridorNM = corridorWidthNM / 4

    let terrainPoints = await withTaskGroup(
      of: (Int, ProcedureTerrainPath.Point).self
    ) { group in
      for i in 0..<pathPoints.count {
        group.addTask {
          let point = pathPoints[i],
            bearing = Self.pathBearing(at: i, in: pathPoints)

          // Sample terrain at 5 lateral offsets perpendicular to the path
          let quarterTurn = Measurement<UnitAngle>(value: 90, unit: .degrees)
          let perpLeft = bearing - quarterTurn,
            perpRight = bearing + quarterTurn

          let sampleOffsets:
            [(distance: Measurement<UnitLength>, bearing: Measurement<UnitAngle>)] = [
              (.init(value: 0, unit: .nauticalMiles), bearing),  // center; bearing is irrelevant
              (.init(value: quarterCorridorNM, unit: .nauticalMiles), perpLeft),
              (.init(value: halfCorridorNM, unit: .nauticalMiles), perpLeft),
              (.init(value: quarterCorridorNM, unit: .nauticalMiles), perpRight),
              (.init(value: halfCorridorNM, unit: .nauticalMiles), perpRight)
            ]

          var maxTerrainFt: Double?
          for offset in sampleOffsets {
            let sampleCoord: CLLocationCoordinate2D
            if offset.distance.value == 0 {
              sampleCoord = point.coordinate
            } else {
              sampleCoord = GeoCalculations.destination(
                from: point.coordinate,
                distance: offset.distance,
                bearing: offset.bearing
              )
            }

            if let elevation = reader.elevation(at: sampleCoord) {
              let elevFt = elevation.converted(to: .feet).value
              if let current = maxTerrainFt {
                maxTerrainFt = max(current, elevFt)
              } else {
                maxTerrainFt = elevFt
              }
            }
          }

          // Ocean-fill: if terrain is still nil, check whether this point is over open ocean
          // (outside all TerrainRegion bounding boxes) or within a loaded region's ocean gap.
          // In either case the true elevation is 0 (sea level). Remaining nils indicate
          // undownloaded regions.
          if maxTerrainFt == nil {
            let regions = TerrainRegion.containing(coordinate: point.coordinate)
            if regions.isEmpty || regions.contains(where: { reader.loadedRegions.contains($0) }) {
              maxTerrainFt = 0
            }
          }

          return (
            i,
            ProcedureTerrainPath.Point(
              coordinate: point.coordinate,
              distanceNM: point.distanceNM,
              track: bearing,
              aircraftAltitudeFt: point.altitudeFt,
              altitudeRestriction: point.altitudeRestriction,
              fixName: point.fixName,
              terrainElevationFt: maxTerrainFt,
              maxObstacleHeightFt: obstaclesByIndex[i]
            )
          )
        }
      }

      var results = [(Int, ProcedureTerrainPath.Point)]()
      results.reserveCapacity(pathPoints.count)
      for await result in group {
        results.append(result)
      }
      return results.sorted { $0.0 < $1.0 }.map(\.1)
    }

    return ProcedureTerrainPath(corridorWidthNM: corridorWidthNM, points: terrainPoints)
  }

  // MARK: - Step 1: Fetch Obstacles

  private func fetchObstacles(
    pathPoints: [ProcedurePath.Point]
  ) -> [ObstacleRecord] {
    let interval = signposter.beginInterval("fetch obstacles", id: signposter.makeSignpostID())
    defer { signposter.endInterval("fetch obstacles", interval) }

    // Compute path extent
    var minLat = Double.greatestFiniteMagnitude,
      maxLat = -Double.greatestFiniteMagnitude,
      minLon = Double.greatestFiniteMagnitude,
      maxLon = -Double.greatestFiniteMagnitude

    for point in pathPoints {
      minLat = min(minLat, point.coordinate.latitude)
      maxLat = max(maxLat, point.coordinate.latitude)
      minLon = min(minLon, point.coordinate.longitude)
      maxLon = max(maxLon, point.coordinate.longitude)
    }

    // Expand by corridor half-width using NearbyFinder bounding box math
    let expansionNM = corridorWidthNM / 2
    let swExpansion = NearbyFinder.boundingBox(
      center: CLLocationCoordinate2D(latitude: minLat, longitude: minLon),
      radiusNM: expansionNM
    )
    let neExpansion = NearbyFinder.boundingBox(
      center: CLLocationCoordinate2D(latitude: maxLat, longitude: maxLon),
      radiusNM: expansionNM
    )

    let expandedMinLat = swExpansion.minLat,
      expandedMaxLat = neExpansion.maxLat,
      expandedMinLon = swExpansion.minLon,
      expandedMaxLon = neExpansion.maxLon

    // Fetch from SwiftData
    let context = ModelContext(modelContainer)
    let descriptor = Obstacle.fetchDescriptor(
      minLat: expandedMinLat,
      maxLat: expandedMaxLat,
      minLon: expandedMinLon,
      maxLon: expandedMaxLon
    )

    do {
      let obstacles = try context.fetch(descriptor)
      return obstacles.map {
        ObstacleRecord(
          coordinate: $0.coordinate,
          heightFtMSL: $0.heightMSL.converted(to: .feet).value
        )
      }
    } catch {
      return []
    }
  }

  // MARK: - Step 2: Assign Obstacles to Path Points

  private func assignObstaclesToPoints(
    obstacles: [ObstacleRecord],
    pathPoints: [ProcedurePath.Point]
  ) -> [Int: Double] {
    let interval = signposter.beginInterval("assign obstacles", id: signposter.makeSignpostID())
    defer { signposter.endInterval("assign obstacles", interval) }

    guard pathPoints.count >= 2 else { return [:] }

    let halfCorridorNM = corridorWidthNM / 2
    let segmentGrid = buildSegmentGrid(pathPoints: pathPoints)
    var result: [Int: Double] = [:]

    for obstacle in obstacles {
      let candidateSegments = segmentGrid.elements(near: obstacle.coordinate)
      guard !candidateSegments.isEmpty else { continue }

      var bestPointIndex: Int?,
        bestCrossTrackNM = Double.greatestFiniteMagnitude

      for segIdx in candidateSegments {
        let segStart = pathPoints[segIdx],
          segEnd = pathPoints[segIdx + 1]
        let segLengthNM = segEnd.distanceNM - segStart.distanceNM
        guard segLengthNM > 0 else { continue }

        let totalSegDist = GeoCalculations.distanceNM(
          from: segStart.coordinate,
          to: segEnd.coordinate
        )
        guard totalSegDist > 0 else { continue }

        let distToObstacle = GeoCalculations.distanceNM(
          from: segStart.coordinate,
          to: obstacle.coordinate
        )

        let segBearing =
          GeoCalculations
          .bearing(from: segStart.coordinate, to: segEnd.coordinate)
          .converted(to: .degrees).value
        let obsBearing =
          GeoCalculations
          .bearing(from: segStart.coordinate, to: obstacle.coordinate)
          .converted(to: .degrees).value

        let angleDiffRad = (obsBearing - segBearing) * .pi / 180
        let alongTrack = distToObstacle * cos(angleDiffRad)

        let fraction = max(0, min(1, alongTrack / totalSegDist))
        let clampedAlongTrackNM = segStart.distanceNM + fraction * segLengthNM

        let clampedCoord = GeoCalculations.interpolate(
          from: segStart.coordinate,
          to: segEnd.coordinate,
          fraction: fraction
        )
        let actualCrossTrack = GeoCalculations.distanceNM(
          from: clampedCoord,
          to: obstacle.coordinate
        )

        if actualCrossTrack < bestCrossTrackNM {
          bestCrossTrackNM = actualCrossTrack
          bestPointIndex = Self.nearestPointIndex(
            atDistanceNM: clampedAlongTrackNM,
            in: pathPoints
          )
        }
      }

      guard bestCrossTrackNM <= halfCorridorNM, let pointIndex = bestPointIndex else { continue }

      if let existing = result[pointIndex] {
        result[pointIndex] = max(existing, obstacle.heightFtMSL)
      } else {
        result[pointIndex] = obstacle.heightFtMSL
      }
    }

    return result
  }

  /// Indexes path segments into a ``CoordinateGrid`` for spatial lookup.
  private func buildSegmentGrid(
    pathPoints: [ProcedurePath.Point]
  ) -> CoordinateGrid<Int> {
    let expansionDeg = corridorWidthNM / 60.0  // 1 NM ≈ 1/60°
    var grid = CoordinateGrid<Int>()

    for segIdx in 0..<(pathPoints.count - 1) {
      let startCoord = pathPoints[segIdx].coordinate,
        endCoord = pathPoints[segIdx + 1].coordinate

      grid.insert(
        segIdx,
        minLat: min(startCoord.latitude, endCoord.latitude) - expansionDeg,
        maxLat: max(startCoord.latitude, endCoord.latitude) + expansionDeg,
        minLon: min(startCoord.longitude, endCoord.longitude) - expansionDeg,
        maxLon: max(startCoord.longitude, endCoord.longitude) + expansionDeg
      )
    }

    return grid
  }

  // MARK: - Nested Types

  /// Lightweight obstacle representation extracted from SwiftData context.
  private struct ObstacleRecord {
    let coordinate: CLLocationCoordinate2D
    let heightFtMSL: Double
  }
}
