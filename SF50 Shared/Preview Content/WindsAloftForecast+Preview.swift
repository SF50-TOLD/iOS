import Foundation

extension WindsAloftForecast {

  /// A sample forecast covering the current time, shaped like a 6-hour NWS bulletin.
  public static var preview: Self { preview(source: .station("SFO")) }

  /// A sample forecast interpolated between stations, as most airports get.
  public static var previewInterpolated: Self { preview(source: .interpolated) }

  /// A sample forecast from Open-Meteo, as airports beyond the NWS bulletins get.
  ///
  /// A model hour applies to that hour alone, unlike a bulletin published for a period hours wide.
  public static var previewModeled: Self {
    let validAt = Date.now.addingTimeInterval(3 * 3600)
    return preview(source: .openMeteo, usePeriod: .init(start: validAt, duration: 3600))
  }

  private static func preview(source: Source, usePeriod: DateInterval? = nil) -> Self {
    let validAt = Date.now.addingTimeInterval(3 * 3600)
    return .init(
      validAt: usePeriod?.start ?? validAt,
      usePeriod: usePeriod
        ?? .init(start: validAt.addingTimeInterval(-4 * 3600), duration: 7 * 3600),
      source: source,
      data: .init(
        // Veering and strengthening with height, as a bulletin's levels usually do, and carried
        // high enough that a departure from a mountain field still has barbs that vary.
        entries: [
          .init(altitudeFt: 3000, windDirectionDeg: 280, windSpeedKts: 18, temperatureC: nil),
          .init(altitudeFt: 6000, windDirectionDeg: 290, windSpeedKts: 24, temperatureC: 11),
          .init(altitudeFt: 9000, windDirectionDeg: 300, windSpeedKts: 31, temperatureC: 5),
          .init(altitudeFt: 12000, windDirectionDeg: 305, windSpeedKts: 39, temperatureC: -1),
          .init(altitudeFt: 18000, windDirectionDeg: 315, windSpeedKts: 52, temperatureC: -14)
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
