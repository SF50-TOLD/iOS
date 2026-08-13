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
  /// - Parameters:
  ///   - forecast: The winds aloft forecast covering the flight, if one does.
  ///   - surfaceTemperature: The measured or forecast temperature at the field.
  ///   - fieldElevation: The elevation of the departure or arrival airport.
  /// - Returns: Observations at each forecast level, or a calm profile from the field upwards.
  public static func windsAloftObservations(
    for forecast: WindsAloftForecast?,
    surfaceTemperature: Measurement<UnitTemperature>?,
    fieldElevation: Measurement<UnitLength>
  ) -> [WindsAloftObservation] {
    guard let forecast else {
      return calmObservations(
        surfaceTemperature: surfaceTemperature,
        fieldElevation: fieldElevation
      )
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

  private static func calmObservations(
    surfaceTemperature: Measurement<UnitTemperature>?,
    fieldElevation: Measurement<UnitLength>
  ) -> [WindsAloftObservation] {
    let surfaceTemperatureC =
      surfaceTemperature?.converted(to: .celsius).value ?? seaLevelStandardTempC
    let fieldElevationFt = fieldElevation.converted(to: .feet).value

    return stride(
      from: fieldElevationFt,
      through: maxWindsAltitudeFt,
      by: windsAltitudeStepFt
    ).map { altitudeFt in
      .init(
        altitudeFt: altitudeFt,
        temperatureC: altitudeFt == fieldElevationFt
          ? surfaceTemperatureC : isaTemperature(altitudeFt: altitudeFt),
        windDirectionDeg: 0,
        windSpeedKts: 0
      )
    }
  }
}
