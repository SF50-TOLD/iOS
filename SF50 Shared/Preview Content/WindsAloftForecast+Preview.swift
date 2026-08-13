import Foundation

extension WindsAloftForecast {

  /// A sample forecast covering the current time, shaped like a 6-hour NWS bulletin.
  public static var preview: Self {
    let validAt = Date.now.addingTimeInterval(3 * 3600)
    return .init(
      validAt: validAt,
      usePeriod: .init(start: validAt.addingTimeInterval(-4 * 3600), duration: 7 * 3600),
      data: .init(
        stationID: "SFO",
        entries: [
          .init(altitudeFt: 3000, windDirectionDeg: 280, windSpeedKts: 18, temperatureC: nil),
          .init(altitudeFt: 6000, windDirectionDeg: 290, windSpeedKts: 24, temperatureC: 11),
          .init(altitudeFt: 9000, windDirectionDeg: 300, windSpeedKts: 31, temperatureC: 5)
        ]
      )
    )
  }
}

extension WindsAloftData.Entry {

  /// Creates an entry from plain values, for previews.
  fileprivate init(
    altitudeFt: Double,
    windDirectionDeg: Double,
    windSpeedKts: Double,
    temperatureC: Double?
  ) {
    self.init(
      altitude: .init(value: altitudeFt, unit: .feet),
      windDirection: .init(value: windDirectionDeg, unit: .degrees),
      windSpeed: .init(value: windSpeedKts, unit: .knots),
      temperature: temperatureC.map { .init(value: $0, unit: .celsius) }
    )
  }
}
