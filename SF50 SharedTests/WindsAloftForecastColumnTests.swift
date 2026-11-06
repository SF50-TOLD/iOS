import Foundation
import RealModule
import Testing

@testable import SF50_Shared

/// The climb profile reads a winds aloft forecast's levels as observations, and a level the
/// forecast reports no temperature for falls back to the standard atmosphere.
struct WindsAloftForecastColumnTests {

  private static let fieldElevation = Measurement(value: 0, unit: UnitLength.feet)

  /// Fifteen degrees above standard at sea level.
  private static let hotEntered = Conditions(temperature: .init(value: 30, unit: .celsius))

  private func column(
    forecast: WindsAloftForecast? = nil,
    conditions: Conditions
  ) -> [ClimbProfileGenerator.WindsAloftObservation] {
    ClimbProfileGenerator.windsAloftObservations(
      for: forecast,
      conditions: conditions,
      fieldElevation: Self.fieldElevation
    )
  }

  @Test
  func `takes the forecast over an entered temperature wherever one covers the flight`() throws {
    let column = column(forecast: .preview, conditions: Self.hotEntered)
    let forecastTemperatures = WindsAloftForecast.preview.data.entries
      .map { $0.temperature?.converted(to: .celsius).value }

    #expect(column.count == forecastTemperatures.count)
    for (observation, forecast) in zip(column, forecastTemperatures) {
      // Levels the forecast reports no temperature for fall back to standard, not to the entered
      // surface reading.
      let expected = forecast ?? isaTemperature(altitudeFt: observation.altitudeFt)
      #expect(observation.temperatureC.isApproximatelyEqual(to: expected, absoluteTolerance: 0.01))
    }
  }
}
