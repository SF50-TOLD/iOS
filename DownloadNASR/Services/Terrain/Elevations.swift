import Foundation

/// A row-major grid of `Int16` elevation samples.
///
/// `Elevations` provides structured access to a flat array of elevation data
/// organized as a 2D grid. All access goes through subscript or
/// ``withUnsafeBufferPointer(_:)`` — the underlying storage is private.
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

  /// Creates a grid backed by an existing array.
  ///
  /// - Precondition: `storage.count` must equal `width * height`.
  init(storage: [Int16], width: Int, height: Int) {
    precondition(
      storage.count == width * height,
      "Storage count (\(storage.count)) must equal width * height (\(width * height))"
    )
    self.width = width
    self.height = height
    self.storage = storage
  }

  /// Creates a square grid filled with a constant value.
  init(size: Int, fill: Int16 = voidValue) {
    self.init(width: size, height: size, fill: fill)
  }

  /// Creates a square grid backed by an existing array.
  ///
  /// - Precondition: `storage.count` must equal `size * size`.
  init(storage: [Int16], size: Int) {
    self.init(storage: storage, width: size, height: size)
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

  /// Returns a new grid downsampled by averaging non-overlapping blocks.
  ///
  /// Each output sample is the mean of a `blockSize × blockSize` region in `self`,
  /// skipping void values. If an entire block is void the output sample is void.
  ///
  /// - Parameters:
  ///   - targetSize: Side length of the (square) output grid.
  ///   - blockSize: Number of source samples per block in each dimension.
  func downsampled(toSize targetSize: Int, blockSize: Int) -> Self {
    var result = Self(size: targetSize)

    for targetRow in 0..<targetSize {
      for targetCol in 0..<targetSize {
        let startRow = targetRow * blockSize,
          startCol = targetCol * blockSize
        var sum: Int32 = 0
        var count = 0

        for row in startRow..<(startRow + blockSize) {
          guard row < height else { continue }
          for col in startCol..<(startCol + blockSize) {
            guard col < width else { continue }
            let value = self[row, col]
            if !Self.isVoid(value) {
              sum += Int32(value)
              count += 1
            }
          }
        }

        result[targetRow, targetCol] =
          count > 0
          ? Int16(sum / Int32(count))
          : Self.voidValue
      }
    }

    return result
  }

  /// Resamples to a square grid using bilinear interpolation.
  ///
  /// Used for Copernicus GLO-30 data which may have non-square tiles at high
  /// latitudes (e.g., 1200×3600 at polar regions).
  func resampled(toSquareOfSize targetSize: Int) -> Self {
    var result = Self(size: targetSize)

    let ratioX = Double(width - 1) / Double(targetSize - 1),
      ratioY = Double(height - 1) / Double(targetSize - 1)

    for targetRow in 0..<targetSize {
      for targetCol in 0..<targetSize {
        let sourceX = Double(targetCol) * ratioX,
          sourceY = Double(targetRow) * ratioY

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

  // MARK: - Serialization

  /// Provides read-only access to the underlying buffer for serialization.
  func withUnsafeBufferPointer<R>(
    _ body: (UnsafeBufferPointer<Int16>) throws -> R
  ) rethrows -> R {
    try storage.withUnsafeBufferPointer(body)
  }

  // MARK: - Subscripts

  subscript(row: Int, col: Int) -> Int16 {
    get { storage[index(row: row, col: col)] }
    set { storage[index(row: row, col: col)] = newValue }
  }
}
