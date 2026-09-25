import Foundation
import SF50_Shared

/// A row-major grid of `Int16` elevation samples.
///
/// `Elevations` provides structured access to a flat array of elevation data
/// organized as a 2D grid. All access goes through the subscript, or ``littleEndianData`` for
/// serialization — the underlying storage is private.
///
/// Width and height are stored separately to support non-square GeoTIFF tiles,
/// with convenience initializers for the common square SRTM case.
struct Elevations: Sendable {

  /// The value used to indicate void/no-data in elevation arrays.
  static let voidValue: Int16 = -32768

  private var storage: [Int16]

  /// Number of columns in the grid.
  let width: Int

  /// Number of rows in the grid.
  let height: Int

  // MARK: - Initializers

  /// Creates a grid filled with a constant value.
  init(width: Int, height: Int, fill: Int16 = voidValue) {
    self.width = width
    self.height = height
    self.storage = [Int16](repeating: fill, count: width * height)
  }

  /// Creates a square grid filled with a constant value.
  init(size: Int, fill: Int16 = voidValue) {
    self.init(width: size, height: size, fill: fill)
  }

  // MARK: - Void Helpers

  /// Whether a given value represents void/no-data.
  static func isVoid(_ value: Int16) -> Bool {
    value == voidValue
  }

  // MARK: - Core Access

  private func index(row: Int, col: Int) -> Int {
    row * width + col
  }

  // MARK: - Resampling

  /// Resamples a Copernicus tile onto a square grid spanning the tile edge to edge, by bilinear
  /// interpolation.
  ///
  /// Copernicus tiles are point-registered: column `i` of `width` lies `i / width` of a degree
  /// east of the tile's west edge, row `j` likewise south of its north edge, and the east and
  /// south edges belong to the neighbouring tiles. Tiles narrow at high latitudes (e.g. 1200×3600
  /// at 70°N). The output repeats both edges, so output sample `k` of `targetSize` sits at source
  /// position `k × width / (targetSize − 1)`; the last row and column fall past the tile's own
  /// samples and take its outermost ones.
  func resampled(toSquareOfSize targetSize: Int) -> Self {
    var result = Self(size: targetSize)

    let ratioX = Double(width) / Double(targetSize - 1),
      ratioY = Double(height) / Double(targetSize - 1)

    for targetRow in 0..<targetSize {
      for targetCol in 0..<targetSize {
        let sourceX = min(Double(targetCol) * ratioX, Double(width - 1)),
          sourceY = min(Double(targetRow) * ratioY, Double(height - 1))

        let x0 = Int(sourceX),
          y0 = Int(sourceY),
          x1 = min(x0 + 1, width - 1),
          y1 = min(y0 + 1, height - 1)

        let xWeight = sourceX - Double(x0),
          yWeight = sourceY - Double(y0)

        let corners = (
          topLeft: self[y0, x0],
          topRight: self[y0, x1],
          bottomLeft: self[y1, x0],
          bottomRight: self[y1, x1]
        )

        let values = [corners.topLeft, corners.topRight, corners.bottomLeft, corners.bottomRight],
          validValues = values.filter { !Self.isVoid($0) }

        switch validValues.count {
          case 0:
            result[targetRow, targetCol] = Self.voidValue
          case 1..<4:
            let sum = validValues.reduce(Int32(0)) { $0 + Int32($1) }
            result[targetRow, targetCol] = Int16(sum / Int32(validValues.count))
          default:
            let top = Double(corners.topLeft) * (1 - xWeight) + Double(corners.topRight) * xWeight,
              bottom =
                Double(corners.bottomLeft) * (1 - xWeight) + Double(corners.bottomRight) * xWeight,
              interpolated = top * (1 - yWeight) + bottom * yWeight
            result[targetRow, targetCol] = Int16(interpolated.rounded())
        }
      }
    }

    return result
  }

  // MARK: - Subscripts

  subscript(row: Int, col: Int) -> Int16 {
    get { storage[index(row: row, col: col)] }
    set { storage[index(row: row, col: col)] = newValue }
  }
}

// MARK: - Serialization

extension Elevations {
  /// Whether every sample is void, as for a tile that is all ocean.
  var isAllVoid: Bool { storage.allSatisfy { $0 == Self.voidValue } }

  /// The samples in row-major order as little-endian `Int16`s, the layout a terrain file stores.
  var littleEndianData: Data {
    var data = Data()
    data.append(contentsOf: storage, .littleEndian)
    return data
  }
}
