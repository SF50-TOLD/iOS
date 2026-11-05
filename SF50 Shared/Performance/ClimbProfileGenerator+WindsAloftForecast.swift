public import Foundation

extension ClimbProfileGenerator {
  /// The atmosphere to climb through, from a winds aloft forecast when one covers the flight.
  ///
  /// Without a forecast the column is the package's standard one: calm, with an entered
  /// temperature carried up as a constant deviation from the standard atmosphere.
  ///
  /// - Parameters:
  ///   - forecast: The winds aloft forecast covering the flight, if one does.
  ///   - conditions: The measured, forecast, or entered conditions at the field.
  ///   - fieldElevation: The elevation of the departure or arrival airport.
  /// - Returns: Observations at each forecast level, or a calm profile from the field upwards.
  public static func windsAloftObservations(
    for forecast: WindsAloftForecast?,
    conditions: Conditions,
    fieldElevation: Measurement<UnitLength>
  ) -> [WindsAloftObservation] {
    guard let forecast else {
      return standardObservations(conditions: conditions, fieldElevation: fieldElevation)
    }

    return forecast.data.entries.map { entry in
      let altitudeFt = entry.altitude.converted(to: .feet).value
      return .init(
        altitudeFt: altitudeFt,
        temperatureC: entry.temperature?.converted(to: .celsius).value
          ?? isaTemperature(altitudeFt: altitudeFt),
        windDirectionDeg: entry.windDirection?.converted(to: .degrees).value ?? 0,
        windSpeedKts: entry.windSpeed.converted(to: .knots).value
      )
    }
  }
}
