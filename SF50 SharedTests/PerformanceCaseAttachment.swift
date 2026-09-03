import Foundation
import Testing

@testable import SF50_Shared

/// The inputs of one performance calculation, attached to a failing test as CSV.
///
/// A golden-number failure reports only that two distances differ. It can't say whether the
/// model moved or the expectation did, because it never names the row that produced them.
/// Attaching the case names it: weight, field elevation, temperature, wind, flap setting, and
/// contamination, alongside the value computed and the value wanted.
///
/// Attachments are recorded on failure only, so a green run carries none.
struct PerformanceCase {

  // MARK: - Type Properties

  private static let attachmentName = "performance-case.csv"
  private static let header = [
    "model", "aircraft", "weight_lb", "elevation_ft", "temperature_C", "wind_direction_deg",
    "wind_speed_kt", "flaps", "ice_protection", "gradient_pct", "surface", "contamination",
    "contamination_depth_in", "result", "value_ft", "expected_ft"
  ]

  // MARK: - Instance Properties

  private let modelKind: ModelKind,
    aircraftType: AircraftType

  private let conditions: Conditions,
    configuration: Configuration,
    runway: RunwayInput,
    contamination: Contamination?

  /// The input half of a CSV row: everything the case holds fixed across its results.
  private var inputFields: [String] {
    [
      modelKind.rawValue,
      String(describing: aircraftType),
      field(configuration.weight.converted(to: .pounds).value),
      field(runway.elevation.converted(to: .feet).value),
      field(conditions.temperature?.converted(to: .celsius).value),
      field(conditions.windDirection?.converted(to: .degrees).value),
      field(conditions.windSpeed?.converted(to: .knots).value),
      String(describing: configuration.flapSetting),
      String(describing: configuration.iceProtection),
      field(Double(runway.gradient) * 100),
      String(describing: runway.surfaceType),
      contamination?.type ?? "none",
      field(
        contamination?.depth.map { Measurement(value: $0, unit: UnitLength.meters) }?
          .converted(to: .inches).value
      )
    ]
  }

  // MARK: - Initializers

  /// Captures the inputs a performance model was built from.
  /// - Parameters:
  ///   - model: The model under test, whose conditions, configuration, runway, and NOTAM
  ///     become the CSV row.
  ///   - aircraftType: The type the model was built for, which it doesn't retain.
  init(for model: BasePerformanceModel, aircraftType: AircraftType) {
    modelKind = model is TabularPerformanceModel ? .tabular : .regression
    self.aircraftType = aircraftType
    conditions = model.conditions
    configuration = model.configuration
    runway = model.runway
    contamination = model.notam?.contamination
  }

  // MARK: - Other Methods

  /// Expects `actualFt` to match a golden distance, attaching this case when it doesn't.
  /// - Parameters:
  ///   - actualFt: The distance the model computed.
  ///   - relativeTolerance: The fraction of `expectedFt` the two may differ by.
  ///   - expectedFt: The golden distance from the AFM.
  ///   - result: What was computed, e.g. `"contaminated landing run"`.
  ///   - sourceLocation: The failing expectation's location.
  func expect(
    _ actualFt: Double,
    isWithin relativeTolerance: Double = 0.01,
    of expectedFt: Double,
    computing result: String,
    sourceLocation: SourceLocation = #_sourceLocation
  ) {
    let matches = actualFt.isApproximatelyEqual(
      to: expectedFt,
      relativeTolerance: relativeTolerance
    )
    if !matches {
      attach(rows: [row(result: result, value: field(actualFt), expected: field(expectedFt))])
    }
    #expect(
      matches,
      "\(result) was \(actualFt) ft, expected \(expectedFt) ft",
      sourceLocation: sourceLocation
    )
  }

  /// Expects `condition` to hold of the distances in `results`, attaching this case and those
  /// distances when it doesn't.
  func expect(
    _ condition: Bool,
    _ comment: Comment,
    results: KeyValuePairs<String, Double>,
    sourceLocation: SourceLocation = #_sourceLocation
  ) {
    if !condition {
      attach(rows: results.map { row(result: $0.key, value: field($0.value), expected: "") })
    }
    #expect(condition, comment, sourceLocation: sourceLocation)
  }

  /// Fails the test with `comment`, attaching this case so the failure names its inputs.
  /// - Parameters:
  ///   - comment: Why the case failed, e.g. the unusable ``Value`` the model returned.
  ///   - result: What was being computed when it failed.
  ///   - sourceLocation: The failure's location.
  func fail(
    _ comment: Comment,
    computing result: String,
    sourceLocation: SourceLocation = #_sourceLocation
  ) {
    attach(rows: [row(result: result, value: "", expected: "")])
    Issue.record(comment, sourceLocation: sourceLocation)
  }

  private func row(result: String, value: String, expected: String) -> [String] {
    inputFields + [result, value, expected]
  }

  private func attach(rows: [[String]]) {
    Attachment.record(
      csv(header: Self.header, rows: rows),
      named: Self.attachmentName
    )
  }

  // MARK: - Subtypes

  /// Which of the two performance models computed the case.
  private enum ModelKind: String {
    case tabular
    case regression
  }
}

/// Attaching the table a lookup ran against, for tests whose subject is the interpolation
/// itself rather than a performance model.
extension DataTable {

  /// Expects `condition` to hold, attaching this table's rows as CSV when it doesn't.
  func expect(
    _ condition: Bool,
    _ comment: Comment,
    sourceLocation: SourceLocation = #_sourceLocation
  ) {
    if !condition { attachRows() }
    #expect(condition, comment, sourceLocation: sourceLocation)
  }

  /// Fails the test with `comment`, attaching this table's rows as CSV.
  func fail(_ comment: Comment, sourceLocation: SourceLocation = #_sourceLocation) {
    attachRows()
    Issue.record(comment, sourceLocation: sourceLocation)
  }

  private func attachRows() {
    guard let firstRow = rows.first else { return }
    let header = (1...inputs(from: firstRow).count).map { "input_\($0)" } + ["output"]
    Attachment.record(
      csv(header: header, rows: rows.map { $0.map(String.init(describing:)) }),
      named: "data-table.csv"
    )
  }
}

/// Renders `rows` under `header` as a CSV document, ready to attach to a failing test.
func csv(header: [String], rows: [[String]]) -> String {
  ([header] + rows).map { $0.joined(separator: ",") }.joined(separator: "\n") + "\n"
}

/// Renders an optional number as a CSV field, leaving it empty when absent.
private func field(_ value: Double?) -> String {
  value.map(String.init(describing:)) ?? ""
}
