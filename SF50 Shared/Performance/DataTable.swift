import Foundation

/// A data table for multi-dimensional interpolation of performance data.
///
/// ``DataTable`` loads CSV data representing digitized AFM charts and performs
/// 1D, 2D, or 3D linear interpolation to compute performance values for
/// arbitrary inputs within the table's range.
///
/// ## Data Format
///
/// CSV files should have N input columns followed by 1 output column. For example,
/// a 3D takeoff distance table has columns: weight, altitude, temperature, distance.
///
/// ## Interpolation
///
/// The table automatically detects dimensionality and uses the appropriate method:
///
/// - **1D**: Linear interpolation between two bounding points
/// - **2D**: Bilinear interpolation between four corner points
/// - **3D**: Trilinear interpolation between eight corner points
///
/// ## Out-of-Bounds Handling
///
/// When inputs fall outside the table's range, behavior depends on the
/// ``Clamping`` mode:
///
/// - ``Clamping/none``: Returns ``.offscaleLow`` or ``.offscaleHigh``
/// - ``Clamping/clampLow``: Clamps to minimum, returns offscale high if above max
/// - ``Clamping/clampHigh``: Clamps to maximum, returns offscale low if below min
/// - ``Clamping/clampBoth``: Clamps to both bounds, never returns offscale
class DataTable {
  private typealias Row = [Double]

  /// The largest absolute difference at which two grid values are considered an
  /// exact match when scanning rows for the requested inputs.
  private static let matchEpsilon = 1e-10

  /// Relative factor applied to a dimension's bound magnitude to derive the
  /// clamping tolerance, providing margin above `Double`'s precision.
  private static let clampToleranceFactor = 1e-9

  private var data: [Row] = []
  private var nInputs: Int = 0

  /// For each input dimension, the sorted-ascending array of unique axis values.
  private var sortedAxes: [[Double]] = []

  /// Per-dimension minimum and maximum input values.
  private var dimMin: [Double] = []
  private var dimMax: [Double] = []

  /// Maps an exact grid coordinate to that row's output value.
  private var cornerIndex: [CornerKey: Double] = [:]

  /// Returns all data rows for iteration
  var rows: [[Double]] {
    return data
  }

  /// Creates a data table by loading CSV data from a file URL.
  ///
  /// - Parameter fileURL: The URL of the CSV file to load.
  /// - Throws: `Errors.badEncoding` if the file cannot be decoded as UTF-8.
  convenience init(fileURL: URL) throws {
    let data = try Data(contentsOf: fileURL)
    guard let string = String(data: data, encoding: .utf8) else {
      throw Errors.badEncoding
    }
    self.init(csv: string)
  }

  /// Creates a data table from a CSV string.
  ///
  /// The CSV format should have N input columns followed by 1 output column.
  /// Each row is parsed as comma-separated floating-point values.
  ///
  /// - Parameter csv: A string containing CSV data with numeric values.
  init(csv: String) {
    let lines = csv.split(whereSeparator: \.isNewline)
    for line in lines {
      let columns = line.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
      let values = columns.compactMap { Double($0) }
      if !values.isEmpty {
        data.append(values)
      }
    }
    if let first = data.first {
      nInputs = first.count - 1
    }
    prepare()
  }

  /// Creates a data table from raw data arrays.
  ///
  /// Each inner array should contain N input values followed by 1 output value.
  /// This initializer is primarily intended for testing purposes.
  ///
  /// - Parameter data: A 2D array where each row contains input values followed by an output value.
  init(data: [[Double]]) {
    self.data = data
    if let first = data.first {
      nInputs = first.count - 1
    }
    prepare()
  }

  /// Precomputes the sorted axes, per-dimension bounds, and corner index used by
  /// the interpolation hot path.
  ///
  /// Called once from each initializer after `data` and `nInputs` are set. The
  /// `data` array is immutable thereafter, so these structures stay valid for the
  /// table's lifetime.
  private func prepare() {
    guard !data.isEmpty, nInputs > 0 else { return }

    sortedAxes = (0..<nInputs).map { dim in
      Array(Set(data.map { $0[dim] })).sorted()
    }
    dimMin = (0..<nInputs).map { dim in data.map { $0[dim] }.min()! }
    dimMax = (0..<nInputs).map { dim in data.map { $0[dim] }.max()! }

    for row in data {
      cornerIndex[CornerKey(coordinates: Array(row.prefix(nInputs)))] = row.last!
    }
  }

  /// Performs multi-dimensional linear interpolation to compute an output value for the given inputs.
  ///
  /// This method supports 1D, 2D, and 3D interpolation. For exact matches in the data table,
  /// the exact value is returned. Otherwise, linear interpolation is performed between
  /// surrounding data points.
  ///
  /// - Parameters:
  ///   - inputs: An array of input values with length matching the table's input-column count.
  ///   - clamping: Optional array of clamping modes for each input dimension. If nil, no clamping is applied.
  ///
  /// - Returns: A `Value<Double>` which may be:
  ///   - `.value(_)` for successful interpolation
  ///   - `.offscaleLow` if inputs are below the table's range
  ///   - `.offscaleHigh` if inputs are above the table's range or interpolation fails
  func value(for inputs: [Double], clamping: [Clamping]? = nil) -> Value<Double> {
    precondition(inputs.count == nInputs, "Input dimension mismatch")

    let clampingModes = clamping ?? Array(repeating: .none, count: nInputs)
    precondition(clampingModes.count == nInputs, "Clamping dimension mismatch")

    // Apply clamping
    var clampedInputs: [Double] = []
    for dim in 0..<nInputs {
      let input = inputs[dim]
      let minVal = dimMin[dim]
      let maxVal = dimMax[dim]

      // Use a relative tolerance for floating-point comparisons based on the magnitude
      // of the bound value. This handles precision loss proportional to value size
      // (e.g., 31000.0 has less precision than 1.0). The factor 1e-9 provides ~6 orders
      // of magnitude margin above Double's ~1e-15 relative precision, accommodating
      // accumulated rounding from arithmetic operations while remaining far smaller
      // than any meaningful data resolution.
      let tolerance = Self.clampToleranceFactor * Swift.max(abs(minVal), abs(maxVal), 1.0)

      switch clampingModes[dim] {
        case .none:
          if input < minVal - tolerance {
            return .offscaleLow
          }
          if input > maxVal + tolerance {
            return .offscaleHigh
          }
          // Clamp to bounds if within tolerance (handles floating-point precision)
          clampedInputs.append(Swift.min(Swift.max(input, minVal), maxVal))
        case .clampLow:
          if input > maxVal + tolerance {
            return .offscaleHigh
          }
          clampedInputs.append(Swift.max(input, minVal))
        case .clampHigh:
          if input < minVal - tolerance {
            return .offscaleLow
          }
          clampedInputs.append(Swift.min(input, maxVal))
        case .clampBoth:
          clampedInputs.append(Swift.min(Swift.max(input, minVal), maxVal))
      }
    }

    // Check for exact match first
    for row in data {
      let matches = (0..<nInputs).allSatisfy {
        abs(row[$0] - clampedInputs[$0]) <= Self.matchEpsilon
      }
      if matches {
        return .value(row.last!)
      }
    }

    // Perform interpolation
    if nInputs == 1 {
      return interpolate1D(input: clampedInputs[0])
    }
    if nInputs == 2 {
      return interpolate2D(inputs: clampedInputs)
    }
    if nInputs == 3 {
      return interpolate3D(inputs: clampedInputs)
    }
    // For higher dimensions, use general n-D interpolation
    return interpolateND(inputs: clampedInputs)
  }

  private func interpolate1D(input: Double) -> Value<Double> {
    guard let (x0, x1) = bounds(forAxis: 0, value: input),
      let lowerValue = cornerValue(at: [x0]),
      let upperValue = cornerValue(at: [x1])
    else {
      return .offscaleHigh
    }

    if x0 == x1 {
      return .value(lowerValue)
    }

    let t = (input - x0) / (x1 - x0)
    return .value(lowerValue + t * (upperValue - lowerValue))
  }

  private func interpolate2D(inputs: [Double]) -> Value<Double> {
    // Find the x bounds from the sorted x axis.
    guard let (x0, x1) = bounds(forAxis: 0, value: inputs[0]) else {
      return .offscaleHigh
    }

    // Restrict the candidate y values to those present at the chosen x bounds.
    let yCandidates = innerCandidates(outer: [x0, x1], innerDim: 1)

    // Find valid y bounds where all 4 corners exist, preferring the tightest bracket.
    var bestY0 = -Double.infinity
    var bestY1 = Double.infinity
    var bestSpan = Double.infinity
    var foundValidBounds = false

    for i in 0..<yCandidates.count {
      for j in i..<yCandidates.count {
        let yLower = yCandidates[i]
        let yUpper = yCandidates[j]

        // Check if input y is within these bounds
        guard yLower <= inputs[1] && inputs[1] <= yUpper else { continue }

        // Check if all 4 corners exist
        let allCornersExist =
          cornerExists(at: [x0, yLower]) && cornerExists(at: [x1, yLower])
          && cornerExists(at: [x0, yUpper]) && cornerExists(at: [x1, yUpper])

        // If all corners exist, check if this is a better (tighter) bound
        if allCornersExist {
          let span = yUpper - yLower
          if span < bestSpan {
            bestY0 = yLower
            bestY1 = yUpper
            bestSpan = span
            foundValidBounds = true
          }
        }
      }
    }

    // If no valid bounds found, return offscale
    guard foundValidBounds else { return .offscaleHigh }
    let (y0, y1) = (bestY0, bestY1)

    // Find the four corner values; if any is missing, return offscale high (no extrapolation)
    guard let v00 = cornerValue(at: [x0, y0]),
      let v01 = cornerValue(at: [x0, y1]),
      let v10 = cornerValue(at: [x1, y0]),
      let v11 = cornerValue(at: [x1, y1])
    else {
      return .offscaleHigh
    }

    // Bilinear interpolation
    let tx = (x0 == x1) ? 0.0 : (inputs[0] - x0) / (x1 - x0)
    let ty = (y0 == y1) ? 0.0 : (inputs[1] - y0) / (y1 - y0)

    let v0 = v00 + tx * (v10 - v00)
    let v1 = v01 + tx * (v11 - v01)

    return .value(v0 + ty * (v1 - v0))
  }

  private func interpolate3D(inputs: [Double]) -> Value<Double> {
    // Find the x bounds, then the y bounds restricted to the chosen x bounds.
    guard let (x0, x1) = bounds(forAxis: 0, value: inputs[0]) else {
      return .offscaleHigh
    }

    let yCandidates = innerCandidates(outer: [x0, x1], innerDim: 1)
    guard let (y0, y1) = bracket(in: yCandidates, value: inputs[1]) else {
      return .offscaleHigh
    }

    // Restrict the candidate z values to those present at the chosen x,y bounds.
    let zCandidates = innerCandidates(outerX: [x0, x1], outerY: [y0, y1], innerDim: 2)

    // Find valid z bounds where all 8 corners exist, preferring the tightest bracket.
    var bestZ0 = -Double.infinity
    var bestZ1 = Double.infinity
    var bestSpan = Double.infinity
    var foundValidBounds = false

    for i in 0..<zCandidates.count {
      for j in i..<zCandidates.count {
        let zLower = zCandidates[i]
        let zUpper = zCandidates[j]

        // Check if input z is within these bounds
        guard zLower <= inputs[2] && inputs[2] <= zUpper else { continue }

        // Check if all 8 corners exist for these bounds
        let allCornersExist =
          cornerExists(at: [x0, y0, zLower]) && cornerExists(at: [x1, y0, zLower])
          && cornerExists(at: [x0, y1, zLower]) && cornerExists(at: [x1, y1, zLower])
          && cornerExists(at: [x0, y0, zUpper]) && cornerExists(at: [x1, y0, zUpper])
          && cornerExists(at: [x0, y1, zUpper]) && cornerExists(at: [x1, y1, zUpper])

        // If all corners exist, check if this is a better (tighter) bound
        if allCornersExist {
          let span = zUpper - zLower
          if span < bestSpan {
            bestZ0 = zLower
            bestZ1 = zUpper
            bestSpan = span
            foundValidBounds = true
          }
        }
      }
    }

    // If no valid bounds found, return offscale
    guard foundValidBounds else { return .offscaleHigh }
    let (z0, z1) = (bestZ0, bestZ1)

    // Find the eight corner values; if any is missing, return offscale high (no extrapolation)
    guard let c0 = cornerValue(at: [x0, y0, z0]),
      let c1 = cornerValue(at: [x1, y0, z0]),
      let c2 = cornerValue(at: [x0, y1, z0]),
      let c3 = cornerValue(at: [x1, y1, z0]),
      let c4 = cornerValue(at: [x0, y0, z1]),
      let c5 = cornerValue(at: [x1, y0, z1]),
      let c6 = cornerValue(at: [x0, y1, z1]),
      let c7 = cornerValue(at: [x1, y1, z1])
    else {
      return .offscaleHigh
    }

    // Trilinear interpolation
    let tx = (x0 == x1) ? 0.0 : (inputs[0] - x0) / (x1 - x0)
    let ty = (y0 == y1) ? 0.0 : (inputs[1] - y0) / (y1 - y0)
    let tz = (z0 == z1) ? 0.0 : (inputs[2] - z0) / (z1 - z0)

    // Interpolate along x
    let v00 = c0 + tx * (c1 - c0)
    let v01 = c2 + tx * (c3 - c2)
    let v10 = c4 + tx * (c5 - c4)
    let v11 = c6 + tx * (c7 - c6)

    // Interpolate along y
    let v0 = v00 + ty * (v01 - v00)
    let v1 = v10 + ty * (v11 - v10)

    // Interpolate along z
    return .value(v0 + tz * (v1 - v0))
  }

  private func interpolateND(inputs _: [Double]) -> Value<Double> {
    // For higher dimensions, we don't support interpolation yet
    // Return offscale to avoid extrapolation
    return .offscaleHigh
  }

  /// Returns the minimum value in the specified input dimension.
  ///
  /// - Parameter dimension: The zero-based index of the input dimension (must be less than the input-column count).
  /// - Returns: The minimum value found in that dimension across all data rows.
  func min(dimension: Int) -> Double {
    precondition((0..<nInputs).contains(dimension), "Invalid dimension")
    return dimMin[dimension]
  }

  /// Returns the maximum value in the specified input dimension.
  ///
  /// - Parameter dimension: The zero-based index of the input dimension (must be less than the input-column count).
  /// - Returns: The maximum value found in that dimension across all data rows.
  func max(dimension: Int) -> Double {
    precondition((0..<nInputs).contains(dimension), "Invalid dimension")
    return dimMax[dimension]
  }

  /// Extracts the input values from a data row.
  ///
  /// - Parameter row: A data row containing N input values followed by 1 output value.
  /// - Returns: An array containing only the input values (all values except the last).
  func inputs(from row: [Double]) -> [Double] {
    precondition(row.count == nInputs + 1, "Invalid row format")
    return Array(row.prefix(nInputs))
  }

  /// Extracts the output value from a data row.
  ///
  /// - Parameter row: A data row containing N input values followed by 1 output value.
  /// - Returns: The output value (the last value in the row).
  func output(from row: [Double]) -> Double {
    precondition(row.count == nInputs + 1, "Invalid row format")
    return row.last!
  }

  /// Finds the bracketing axis values around `value` on the given input dimension.
  ///
  /// Bisects `sortedAxes[dim]` to find the largest axis value `<= value` (lower)
  /// and the smallest axis value `>= value` (upper). When `value` lies below the
  /// smallest or above the largest axis value, the corresponding bound is the
  /// infinite sentinel, so downstream corner lookups miss and interpolation
  /// returns `.offscaleHigh` — matching the original behavior.
  private func bounds(forAxis dim: Int, value: Double) -> (lower: Double, upper: Double)? {
    return bracket(in: sortedAxes[dim], value: value)
  }

  /// Finds the bracketing values around `value` within a sorted-ascending array.
  ///
  /// Returns the largest element `<= value` as the lower bound and the smallest
  /// element `>= value` as the upper bound, falling back to `-infinity` /
  /// `+infinity` when no element satisfies the corresponding inequality.
  private func bracket(in axis: [Double], value: Double) -> (lower: Double, upper: Double)? {
    var lower = -Double.infinity
    var upper = Double.infinity

    // Largest axis value <= value: rightmost element not exceeding value.
    var low = 0
    var high = axis.count
    while low < high {
      let mid = low + (high - low) / 2
      if axis[mid] <= value {
        lower = axis[mid]
        low = mid + 1
      } else {
        high = mid
      }
    }

    // Smallest axis value >= value: leftmost element not below value.
    low = 0
    high = axis.count
    while low < high {
      let mid = low + (high - low) / 2
      if axis[mid] >= value {
        upper = axis[mid]
        high = mid
      } else {
        low = mid + 1
      }
    }

    return (lower, upper)
  }

  /// Returns the sorted-ascending inner-axis values present at the given outer-axis bounds.
  ///
  /// Mirrors the original restriction of candidate values to rows whose leading
  /// input column matches one of the chosen outer bounds.
  private func innerCandidates(outer: [Double], innerDim: Int) -> [Double] {
    var values = Set<Double>()
    for row in data where outer.contains(row[0]) {
      values.insert(row[innerDim])
    }
    return values.sorted()
  }

  /// Returns the sorted-ascending inner-axis values present at the given x and y bounds.
  private func innerCandidates(outerX: [Double], outerY: [Double], innerDim: Int) -> [Double] {
    var values = Set<Double>()
    for row in data where outerX.contains(row[0]) && outerY.contains(row[1]) {
      values.insert(row[innerDim])
    }
    return values.sorted()
  }

  /// Looks up the output value stored at an exact grid coordinate.
  private func cornerValue(at coordinates: [Double]) -> Double? {
    return cornerIndex[CornerKey(coordinates: coordinates)]
  }

  /// Reports whether a row exists at an exact grid coordinate.
  private func cornerExists(at coordinates: [Double]) -> Bool {
    return cornerIndex[CornerKey(coordinates: coordinates)] != nil
  }

  /// An exact grid coordinate keying a row's output value in ``cornerIndex``.
  ///
  /// Coordinates are taken verbatim from the table's data columns, so the stored
  /// `Double` bit patterns are identical to the axis values used for lookups and
  /// equality is exact — reproducing the original string-equality corner test.
  private struct CornerKey: Hashable {
    let coordinates: [Double]
  }

  /// Errors that can occur during data table operations.
  enum Errors: LocalizedError {
    /// The file data could not be decoded as UTF-8.
    case badEncoding

    var errorDescription: String? {
      String(localized: "Data table couldn’t be loaded.")
    }

    var failureReason: String? {
      switch self {
        case .badEncoding:
          String(localized: "The file data could not be decoded as UTF-8.")
      }
    }
  }

  /// Clamping modes for input dimensions during interpolation.
  ///
  /// Clamping controls how out-of-bounds input values are handled.
  enum Clamping {
    /// No clamping - return offscale values if inputs are outside the table's range.
    case none
    /// Clamp only the lower bound - inputs below minimum are clamped to minimum.
    case clampLow
    /// Clamp only the upper bound - inputs above maximum are clamped to maximum.
    case clampHigh
    /// Clamp both bounds - inputs are constrained to [min, max] range.
    case clampBoth
  }
}
