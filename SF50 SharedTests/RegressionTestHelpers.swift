import Foundation
import Testing

@testable import SF50_Shared

/// Validates that a regression model's predictions fall within acceptable error bounds
/// for the training data. Allows up to 20% of points to fall outside 95% CI, as
/// polynomial regression residuals often have non-normal distributions.
func validateRegressionPredictions<Model: BasePerformanceModel>(
  _ dataTable: DataTable,
  inputExtractor: ([Double]) -> (weight: Double, altitude: Double, temperature: Double) = {
    inputs in
    (weight: inputs[0], altitude: inputs[1], temperature: inputs[2])
  },
  configBuilder: (Double) -> Configuration = { weight in
    Helper.createTestConfiguration(weight: weight)
  },
  modelBuilder: (Conditions, Configuration, RunwayInput) -> Model,
  valueExtractor: (Model) -> Value<Double>,
  aircraftType: AircraftType,
  testName: String
) {
  var totalPoints = 0
  var missedRows: [[String]] = []

  for row in dataTable.rows {
    let inputs = dataTable.inputs(from: row)
    let expected = dataTable.output(from: row)

    let extracted = inputExtractor(inputs)
    let weight = extracted.weight
    let altitude = extracted.altitude
    let temperature = extracted.temperature

    let conditions = Helper.createTestConditions(temperature: temperature)
    let config = configBuilder(weight)
    let runway = Helper.createTestRunway(elevation: altitude)

    let model = modelBuilder(conditions, config, RunwayInput(from: runway, airport: runway.airport))
    let result = valueExtractor(model)

    guard case .valueWithUncertainty(let predicted, let uncertainty) = result else {
      PerformanceCase(for: model, aircraftType: aircraftType)
        .fail(
          "\(testName): expected a value with uncertainty, got \(result)",
          computing: testName
        )
      continue
    }

    totalPoints += 1
    if !result.contains(expected, confidenceLevel: 0.95) {
      missedRows.append(
        [weight, altitude, temperature, expected, predicted, uncertainty].map(
          String.init(describing:)
        )
      )
    }
  }

  guard totalPoints > 0 else {
    Issue.record(
      "\(testName): none of the \(dataTable.rows.count) training rows produced a value with uncertainty"
    )
    return
  }

  let failureRate = Double(missedRows.count) / Double(totalPoints)
  if failureRate > 0.20 {
    Attachment.record(
      csv(
        header: [
          "weight_lb", "altitude_ft", "temperature_C", "expected", "predicted", "uncertainty"
        ],
        rows: missedRows
      ),
      named: "\(testName) missed rows.csv"
    )
  }
  #expect(
    failureRate <= 0.20,
    "\(testName): Failure rate \(String(format: "%.1f%%", failureRate * 100)) exceeds 20% threshold (\(missedRows.count)/\(totalPoints) points outside 95% CI)"
  )
}
