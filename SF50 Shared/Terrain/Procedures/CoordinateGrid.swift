import CoreLocation
import Foundation

/// A spatial index that maps coordinate-based items into a fixed-size
/// latitude/longitude grid for fast neighbor lookups.
///
/// Items are inserted into every grid cell their bounding box touches.
/// Queries return all items in a cell and its 8 neighbors, avoiding
/// full linear scans.
struct CoordinateGrid<Element> {
  /// Grid cell size in degrees (~0.5 NM at mid-latitudes).
  static var cellSizeDeg: Double { 0.008 }

  private var storage: [Int: [Int: [Element]]] = [:]

  /// Inserts an element into every cell overlapping the given bounding box.
  mutating func insert(
    _ element: Element,
    minLat: Double,
    maxLat: Double,
    minLon: Double,
    maxLon: Double
  ) {
    let cellSize = Self.cellSizeDeg

    let minLatBucket = Int(floor(minLat / cellSize)),
      maxLatBucket = Int(floor(maxLat / cellSize)),
      minLonBucket = Int(floor(minLon / cellSize)),
      maxLonBucket = Int(floor(maxLon / cellSize))

    for latB in minLatBucket...maxLatBucket {
      for lonB in minLonBucket...maxLonBucket {
        storage[latB, default: [:]][lonB, default: []].append(element)
      }
    }
  }

  /// Returns all elements in the cell containing `coordinate` and its 8 neighbors.
  func elements(near coordinate: CLLocationCoordinate2D) -> [Element] {
    let cellSize = Self.cellSizeDeg
    let latBucket = Int(floor(coordinate.latitude / cellSize)),
      lonBucket = Int(floor(coordinate.longitude / cellSize))

    var result: [Element] = []
    for dLat in -1...1 {
      for dLon in -1...1 {
        if let row = storage[latBucket + dLat],
          let elements = row[lonBucket + dLon]
        {
          result.append(contentsOf: elements)
        }
      }
    }
    return result
  }
}
