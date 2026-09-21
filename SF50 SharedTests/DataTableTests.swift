import RealModule
import Testing

@testable import SF50_Shared

struct DataTableTests {

  // MARK: - 1D Interpolation Tests

  @Test
  func `exact match 1D`() {
    let data = [
      [1000.0, 100.0],
      [2000.0, 200.0],
      [3000.0, 300.0]
    ]
    let table = DataTable(data: data)

    let result = table.value(for: [2000.0])
    #expect(result == .value(200.0))
  }

  @Test
  func `linear interpolation 1D`() {
    let data = [
      [1000.0, 100.0],
      [2000.0, 200.0]
    ]
    let table = DataTable(data: data)

    let result = table.value(for: [1500.0])
    #expect(result == .value(150.0))

    // Test with non-exact interpolation
    let result2 = table.value(for: [1234.5])
    guard case .value(let value) = result2 else {
      table.fail("Expected interpolated value, got \(result2)")
      return
    }
    #expect(value.isApproximatelyEqual(to: 123.45, relativeTolerance: 0.0001))
  }

  @Test
  func `offscale 1D`() {
    let data = [
      [1000.0, 100.0],
      [2000.0, 200.0]
    ]
    let table = DataTable(data: data)

    #expect(table.value(for: [500.0]) == .offscaleLow(clamped: nil))
    #expect(table.value(for: [2500.0]) == .offscaleHigh(clamped: nil))
  }

  @Test
  func `clamping hands back the edge figure marked as offscale`() {
    let data = [
      [1000.0, 100.0],
      [2000.0, 200.0]
    ]
    let table = DataTable(data: data)

    #expect(table.value(for: [500.0], clamping: [.clampLow]) == .offscaleLow(clamped: 100.0))
    #expect(table.value(for: [2500.0], clamping: [.clampHigh]) == .offscaleHigh(clamped: 200.0))
    #expect(table.value(for: [500.0], clamping: [.clampBoth]) == .offscaleLow(clamped: 100.0))
    #expect(table.value(for: [2500.0], clamping: [.clampBoth]) == .offscaleHigh(clamped: 200.0))
  }

  @Test
  func `clamping leaves an in-range figure definite`() {
    let table = DataTable(data: [
      [1000.0, 100.0],
      [2000.0, 200.0]
    ])

    #expect(table.value(for: [1500.0], clamping: [.clampBoth]) == .value(150.0))
    #expect(table.value(for: [1000.0], clamping: [.clampBoth]) == .value(100.0))
  }

  // MARK: - 2D Interpolation Tests

  @Test
  func `exact match 2D`() {
    let data = [
      [1000.0, 10.0, 100.0],
      [1000.0, 20.0, 110.0],
      [2000.0, 10.0, 200.0],
      [2000.0, 20.0, 220.0]
    ]
    let table = DataTable(data: data)

    let result = table.value(for: [1000.0, 20.0])
    #expect(result == .value(110.0))
  }

  @Test
  func `bilinear interpolation 2D`() {
    let data = [
      [1000.0, 10.0, 100.0],
      [1000.0, 20.0, 200.0],
      [2000.0, 10.0, 300.0],
      [2000.0, 20.0, 400.0]
    ]
    let table = DataTable(data: data)

    // Interpolate at center point
    let result = table.value(for: [1500.0, 15.0])
    #expect(result == .value(250.0))
  }

  @Test
  func `sparse data interpolation 3D`() {
    // Test with sparse data similar to actual CSV structure
    let data = [
      // Include ISA temperatures
      [6000.0, 7000.0, 1.1316, 2737.0],
      [6000.0, 7000.0, 20.0, 3960.0],
      [6000.0, 7000.0, 30.0, 4905.0],
      [6000.0, 8000.0, 20.0, 4429.0],
      [6000.0, 8000.0, 30.0, 5488.0]
    ]
    let table = DataTable(data: data)

    // Should interpolate between 20 and 30, ignoring ISA value
    let result = table.value(for: [6000.0, 7000.0, 25.0])
    guard case .value(let value) = result else {
      table.fail("Expected an interpolated value, got \(result)")
      return
    }
    let expected = 3960.0 + 0.5 * (4905.0 - 3960.0)
    table.expect(
      value.isApproximatelyEqual(to: expected, relativeTolerance: 0.0001),
      "Interpolated \(value), expected \(expected)"
    )
  }

  @Test
  func `a ragged 2D table names the side the input ran off`() {
    // The coldest temperature is tabulated at sea level only, so the rows bracketing 1500 ft carry
    // nothing below 0 °C even though the table as a whole reaches -20 °C.
    let table = DataTable(data: [
      [0.0, -20.0, 100.0],
      [0.0, 0.0, 120.0],
      [1000.0, 0.0, 200.0],
      [1000.0, 20.0, 220.0],
      [2000.0, 0.0, 300.0],
      [2000.0, 20.0, 320.0]
    ])

    #expect(table.value(for: [1500.0, -10.0]) == .offscaleLow(clamped: nil))
    #expect(table.value(for: [1500.0, 10.0]) == .value(260.0))
  }

  @Test
  func `a hole in a 2D table reports no figure rather than an edge`() {
    // Every candidate bracket around 5 °C is missing a corner, but 5 °C is inside the range the
    // table covers on both axes — so neither edge is the honest answer.
    let table = DataTable(data: [
      [0.0, 0.0, 10.0],
      [0.0, 10.0, 20.0],
      [1000.0, 10.0, 200.0],
      [1000.0, 20.0, 300.0]
    ])

    #expect(table.value(for: [500.0, 5.0]) == .notAvailable)
    #expect(table.value(for: [500.0, 15.0]) == .notAvailable)
  }

  @Test
  func `a four-dimensional table reports no figure`() {
    // Four inputs are not interpolated, which is a gap in this type rather than an edge of the
    // chart — naming an edge would describe the inputs, and they were never looked at.
    let table = DataTable(data: [
      [0.0, 0.0, 0.0, 0.0, 10.0],
      [1.0, 1.0, 1.0, 1.0, 20.0]
    ])

    #expect(table.value(for: [0.5, 0.5, 0.5, 0.5]) == .notAvailable)
  }

  @Test
  func `a 3D table ragged in altitude widens past the hole`() {
    // f(x, y, z) = 0.1x + 0.02y + 2z, tabulated at every corner except the middle altitude's
    // heavier weight — the shape the AFM tables take, where the altitudes tabulated vary by
    // weight. The adjacent altitude bracket around 2500 is therefore incomplete at every
    // temperature, and the complete box is one step out.
    let table = DataTable(data: [
      [0.0, 0.0, 0.0, 0.0],
      [1000.0, 0.0, 0.0, 100.0],
      [0.0, 0.0, 20.0, 40.0],
      [1000.0, 0.0, 20.0, 140.0],
      [0.0, 5000.0, 0.0, 100.0],
      [0.0, 5000.0, 20.0, 140.0],
      [0.0, 10000.0, 0.0, 200.0],
      [1000.0, 10000.0, 0.0, 300.0],
      [0.0, 10000.0, 20.0, 240.0],
      [1000.0, 10000.0, 20.0, 340.0]
    ])

    // Taking the adjacent altitude pair and only widening temperature found nothing here.
    #expect(table.value(for: [500.0, 2500.0, 10.0]) == .value(120.0))
  }

  // MARK: - Edge Cases

  @Test
  func `single data point`() {
    let data = [[1000.0, 100.0]]
    let table = DataTable(data: data)

    // Exact match
    #expect(table.value(for: [1000.0]) == .value(100.0))

    // Off scale
    #expect(table.value(for: [999.0]) == .offscaleLow(clamped: nil))
    #expect(table.value(for: [1001.0]) == .offscaleHigh(clamped: nil))
  }

  // MARK: - CSV Parsing Tests

  @Test
  func `CSV parsing`() {
    let csv = """
      weight,altitude,temperature,value
      5000,7000,20,3300
      5000,7000,30,4088
      6000,7000,20,3960
      6000,7000,30,4905
      """

    let table = DataTable(csv: csv)

    // Test exact match
    let result = table.value(for: [5000.0, 7000.0, 20.0])
    table.expect(result == .value(3300.0), "Exact match returned \(result)")

    // Test interpolation
    let interpResult = table.value(for: [5500.0, 7000.0, 25.0])
    guard case .value(let value) = interpResult else {
      table.fail("Expected an interpolated value, got \(interpResult)")
      return
    }
    table.expect(
      value > 3300.0 && value < 4905.0,
      "Interpolated \(value), which is outside the bracketing values"
    )
  }

  // MARK: - Min/Max Tests

  @Test
  func `min and max values`() {
    let data = [
      [1000.0, 10.0, 100.0],
      [2000.0, 20.0, 200.0],
      [3000.0, 30.0, 300.0]
    ]
    let table = DataTable(data: data)

    table.expect(table.min(dimension: 0) == 1000.0, "Minimum of dimension 0")
    table.expect(table.max(dimension: 0) == 3000.0, "Maximum of dimension 0")

    table.expect(table.min(dimension: 1) == 10.0, "Minimum of dimension 1")
    table.expect(table.max(dimension: 1) == 30.0, "Maximum of dimension 1")
  }
}
