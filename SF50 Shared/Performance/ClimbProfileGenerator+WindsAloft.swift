import Foundation

extension ClimbProfileGenerator {

  /// The altitude of the highest level a synthesized profile extends to.
  private static let maxWindsAltitudeFt: Double = 18000

  /// The spacing between the levels of a synthesized profile.
  private static let windsAltitudeStepFt: Double = 3000

  /// The atmosphere to climb through, from a winds aloft forecast when one covers the flight.
  ///
  /// Without a forecast the winds are calm rather than the surface wind carried aloft: surface
  /// wind describes the first few hundred feet and nothing above, so extending it up through the
  /// climb would invent a wind field rather than admit there is none.
  ///
  /// The temperature is treated differently: one the pilot typed in is carried up the column as a
  /// constant deviation from the standard atmosphere, while a reported one leaves the column
  /// standard.
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
      return synthesizedObservations(conditions: conditions, fieldElevation: fieldElevation)
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

  /// A calm column standing in for a forecast that doesn't cover the flight.
  ///
  /// The field's own level takes the reported temperature whatever its source: an observation
  /// describes the surface, and that is the surface.
  ///
  /// Above it, only a temperature the pilot *entered* is carried up, offset from the standard
  /// atmosphere by the deviation measured at the field — so a day that is fifteen degrees above
  /// standard stays fifteen above all the way up the climb. Entered weather is a statement about
  /// the atmosphere to fly through, made when nothing else is available; a downloaded surface
  /// report is an observation of the surface, and stays there, because a forecast covering the
  /// levels above it is what the app uses instead.
  ///
  /// A constant deviation is the standard-atmosphere assumption pilots plan on. It describes a
  /// well-mixed air mass, and overstates the temperature aloft under a surface inversion.
  private static func synthesizedObservations(
    conditions: Conditions,
    fieldElevation: Measurement<UnitLength>
  ) -> [WindsAloftObservation] {
    let fieldElevationFt = fieldElevation.converted(to: .feet).value
    // Read through `temperature(at:)` rather than the raw property, so a report that leaves the
    // temperature out — and a standard-atmosphere report at a field far above sea level — start
    // from the standard temperature *there* rather than from sea level's.
    let surfaceTemperatureC = conditions.temperature(at: fieldElevation)
      .converted(to: .celsius).value
    // Nothing to carry unless the pilot entered a temperature: a column with no reading of its own
    // deviates from standard by nothing.
    let deviationC =
      conditions.source == .entered && conditions.temperature != nil
      ? surfaceTemperatureC - isaTemperature(altitudeFt: fieldElevationFt) : 0

    return stride(
      from: fieldElevationFt,
      through: maxWindsAltitudeFt,
      by: windsAltitudeStepFt
    ).map { altitudeFt in
      .init(
        altitudeFt: altitudeFt,
        temperatureC: altitudeFt == fieldElevationFt
          ? surfaceTemperatureC : isaTemperature(altitudeFt: altitudeFt) + deviationC,
        windDirectionDeg: 0,
        windSpeedKts: 0
      )
    }
  }
}
