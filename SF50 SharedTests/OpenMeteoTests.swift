import CoreLocation
import Foundation
import RealModule
import Testing

@testable import SF50_Shared

/// A three-hour Open-Meteo response, abridged to the levels that carry the behavior under test.
///
/// The model's terrain stands at 100 m, so the 1000 hPa level — which the model places below it —
/// is extrapolated rather than forecast. 700 hPa carries no wind speed, and 600 hPa is omitted
/// entirely, as the API omits a variable it doesn't publish rather than sending a column of nulls.
private enum Forecast {
  /// The first hour of the response, 2026-08-15 12:00Z.
  static let firstHour = Date(timeIntervalSince1970: 1_786_795_200)

  /// The last instant the response covers, one second before its third hour ends.
  static let lastInstant = firstHour.addingTimeInterval(3 * 3600 - 1)

  static let json = """
    {
      "latitude": 37.75,
      "longitude": -122.25,
      "elevation": 100.0,
      "generationtime_ms": 0.42,
      "utc_offset_seconds": 0,
      "timezone": "GMT",
      "hourly_units": { "time": "unixtime", "temperature_2m": "°C" },
      "hourly": {
        "time": [1786795200, 1786798800, 1786802400],
        "temperature_2m": [18.4, 19.1, 19.6],
        "dew_point_2m": [11.2, 11.0, 10.8],
        "pressure_msl": [1016.3, 1016.1, 1015.8],
        "wind_speed_10m": [9.7, 11.2, 12.4],
        "wind_direction_10m": [285, 290, 292],
        "temperature_1000hPa": [17.9, 18.6, 19.0],
        "wind_speed_1000hPa": [10.1, 11.6, 12.9],
        "wind_direction_1000hPa": [284, 289, 291],
        "geopotential_height_1000hPa": [60.0, 61.0, 62.0],
        "cloud_cover_1000hPa": [0, 0, 0],
        "relative_humidity_1000hPa": [55, 56, 57],
        "temperature_925hPa": [13.2, 13.5, 13.7],
        "wind_speed_925hPa": [18.0, 19.5, 20.1],
        "wind_direction_925hPa": [295, 297, 298],
        "geopotential_height_925hPa": [762.0, 763.0, 764.0],
        "cloud_cover_925hPa": [95, 90, 85],
        "relative_humidity_925hPa": [88, 86, 84],
        "temperature_850hPa": [8.4, 8.6, 8.8],
        "wind_speed_850hPa": [24.6, 25.9, 26.3],
        "wind_direction_850hPa": [300, 301, 303],
        "geopotential_height_850hPa": [1487.0, 1489.0, 1491.0],
        "cloud_cover_850hPa": [40, 38, 35],
        "relative_humidity_850hPa": [62, 60, 58],
        "temperature_700hPa": [-2.1, -2.0, -1.8],
        "wind_direction_700hPa": [310, 311, 312],
        "geopotential_height_700hPa": [3055.0, 3057.0, 3060.0],
        "cloud_cover_700hPa": [70, 68, 66],
        "relative_humidity_700hPa": [91, 90, 89]
      }
    }
    """

  /// The same response as a two-location list, the shape a multi-coordinate request answers with.
  static var listJSON: String { "[\(json), \(json)]" }

  static var response: OpenMeteoResponse {
    get throws { try decoder.decode(OpenMeteoResponse.self, from: Data(json.utf8)) }
  }

  static var listResponses: [OpenMeteoResponse] {
    get throws { try decoder.decode([OpenMeteoResponse].self, from: Data(listJSON.utf8)) }
  }

  private static var decoder: JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .secondsSince1970
    return decoder
  }
}

struct OpenMeteoConditionsTests {

  @Test("Reads the hour covering the requested time, in the units requested")
  func conditionsAtRequestedHour() throws {
    let midSecondHour = Forecast.firstHour.addingTimeInterval(3600 + 900)
    let conditions = try #require(Conditions(openMeteo: try Forecast.response, at: midSecondHour))

    #expect(
      conditions.validTime
        == .init(
          start: Forecast.firstHour.addingTimeInterval(3600),
          duration: 3600
        )
    )
    #expect(conditions.windDirection == .init(value: 290, unit: .degrees))
    #expect(conditions.windSpeed == .init(value: 11.2, unit: .knots))
    #expect(conditions.temperature == .init(value: 19.1, unit: .celsius))
    #expect(conditions.dewpoint == .init(value: 11.0, unit: .celsius))
    #expect(conditions.seaLevelPressure == .init(value: 1016.1, unit: .hectopascals))
    #expect(conditions.source == .downloaded(.openMeteo))
  }

  @Test("Reads the hour a time falls on the start of, not the one it ends")
  func conditionsOnTheHour() throws {
    let secondHour = Forecast.firstHour.addingTimeInterval(3600)
    let conditions = try #require(Conditions(openMeteo: try Forecast.response, at: secondHour))

    #expect(conditions.validTime.start == secondHour)
    #expect(conditions.temperature == .init(value: 19.1, unit: .celsius))
  }

  @Test("Has no conditions for a time the forecast doesn’t reach")
  func conditionsBeyondForecast() throws {
    let response = try Forecast.response
    #expect(Conditions(openMeteo: response, at: Forecast.firstHour.addingTimeInterval(-1)) == nil)
    #expect(Conditions(openMeteo: response, at: Forecast.lastInstant) != nil)
    #expect(
      Conditions(openMeteo: response, at: Forecast.lastInstant.addingTimeInterval(1)) == nil
    )
  }
}

struct OpenMeteoWindsAloftTests {

  @Test("Places each level at its geopotential height, lowest first")
  func levelAltitudes() throws {
    let forecast = try #require(
      WindsAloftForecast(openMeteo: try Forecast.response, at: Forecast.firstHour)
    )

    let altitudesFt = forecast.data.entries.map { $0.altitude.converted(to: .feet).value }
    #expect(altitudesFt == altitudesFt.sorted())
    #expect(altitudesFt.count == 2)
    // 762 m and 1487 m, the 925 and 850 hPa levels.
    #expect(altitudesFt[0].isApproximatelyEqual(to: 2500, absoluteTolerance: 1))
    #expect(altitudesFt[1].isApproximatelyEqual(to: 4879, absoluteTolerance: 1))
  }

  @Test("Drops levels the model puts below its own terrain, and levels missing a wind")
  func unusableLevels() throws {
    let forecast = try #require(
      WindsAloftForecast(openMeteo: try Forecast.response, at: Forecast.firstHour)
    )
    let altitudesM = forecast.data.entries.map { $0.altitude.converted(to: .meters).value }

    // 1000 hPa sits at 60 m, below the model's 100 m terrain.
    #expect(!altitudesM.contains { $0.isApproximatelyEqual(to: 60, absoluteTolerance: 1) })
    // 700 hPa reports a direction but no speed.
    #expect(!altitudesM.contains { $0.isApproximatelyEqual(to: 3055, absoluteTolerance: 1) })
  }

  @Test("Applies to the single hour it was forecast for, and says where it came from")
  func provenanceAndPeriod() throws {
    let forecast = try #require(
      WindsAloftForecast(openMeteo: try Forecast.response, at: Forecast.firstHour)
    )

    #expect(forecast.source == .openMeteo)
    #expect(forecast.validAt == Forecast.firstHour)
    #expect(forecast.usePeriod == .init(start: Forecast.firstHour, duration: 3600))
  }

  @Test("Carries each level’s wind and temperature")
  func levelValues() throws {
    let forecast = try #require(
      WindsAloftForecast(openMeteo: try Forecast.response, at: Forecast.firstHour)
    )
    let lowest = try #require(forecast.data.entries.first)

    #expect(lowest.windDirection == .init(value: 295, unit: .degrees))
    #expect(lowest.windSpeed == .init(value: 18.0, unit: .knots))
    #expect(lowest.temperature == .init(value: 13.2, unit: .celsius))
  }

  @Test("Has no winds aloft for a time the forecast doesn’t reach")
  func beyondForecast() throws {
    let response = try Forecast.response
    #expect(WindsAloftForecast(openMeteo: response, at: Forecast.lastInstant) != nil)
    #expect(
      WindsAloftForecast(openMeteo: response, at: Forecast.lastInstant.addingTimeInterval(1))
        == nil
    )
  }
}

struct OpenMeteoAtmosphericProfileTests {

  private static let coordinate = CLLocationCoordinate2D(latitude: 37.75, longitude: -122.25)

  @Test("Reads cloud cover and humidity as fractions, at each level’s geopotential height")
  func levelValues() throws {
    let profile = try #require(
      AtmosphericProfile(
        openMeteo: try Forecast.response,
        at: Self.coordinate,
        for: Forecast.firstHour
      )
    )
    let lowest = try #require(profile.levels.first)

    #expect(
      lowest.altitude.converted(to: .feet).value.isApproximatelyEqual(
        to: 2500,
        absoluteTolerance: 1
      )
    )
    #expect(lowest.temperature == .init(value: 13.2, unit: .celsius))
    #expect(
      try #require(lowest.cloudCover).isApproximatelyEqual(to: 0.95, absoluteTolerance: 0.001)
    )
    #expect(
      try #require(lowest.relativeHumidity).isApproximatelyEqual(to: 0.88, absoluteTolerance: 0.001)
    )
  }

  @Test("Drops levels the model puts below its own terrain, but keeps ones missing a wind")
  func unusableLevels() throws {
    let profile = try #require(
      AtmosphericProfile(
        openMeteo: try Forecast.response,
        at: Self.coordinate,
        for: Forecast.firstHour
      )
    )
    let altitudesM = profile.levels.map { $0.altitude.converted(to: .meters).value }

    // 1000 hPa sits at 60 m, below the model's 100 m terrain.
    #expect(!altitudesM.contains { $0.isApproximatelyEqual(to: 60, absoluteTolerance: 1) })
    // 700 hPa reports no wind, which a profile doesn't carry and so doesn't miss.
    #expect(altitudesM.contains { $0.isApproximatelyEqual(to: 3055, absoluteTolerance: 1) })
  }

  @Test("Carries the lowest and highest levels beyond the range they were reported over")
  func clampsOutsideReportedRange() throws {
    let profile = try #require(
      AtmosphericProfile(
        openMeteo: try Forecast.response,
        at: Self.coordinate,
        for: Forecast.firstHour
      )
    )
    let lowest = try #require(profile.levels.first)

    // Well below the model's lowest usable level, where a climb profile still needs an answer.
    let atSurface = try #require(profile.level(at: .init(value: 0, unit: .feet)))
    #expect(atSurface.temperature == lowest.temperature)
    #expect(atSurface.cloudCover == lowest.cloudCover)
    #expect(atSurface.altitude == .init(value: 0, unit: .feet))
  }

  @Test("Interpolates between the levels bracketing an altitude")
  func interpolatesBetweenLevels() throws {
    let profile = try #require(
      AtmosphericProfile(
        openMeteo: try Forecast.response,
        at: Self.coordinate,
        for: Forecast.firstHour
      )
    )

    // Halfway between 762 m (13.2 °C) and 1487 m (8.4 °C).
    let midpoint = try #require(
      profile.level(at: .init(value: (762.0 + 1487.0) / 2, unit: .meters))
    )
    #expect(
      try #require(midpoint.temperature).converted(to: .celsius).value
        .isApproximatelyEqual(to: (13.2 + 8.4) / 2, absoluteTolerance: 0.01)
    )
  }

  @Test("Decodes the list a multi-coordinate request answers with")
  func decodesLocationList() throws {
    let responses = try Forecast.listResponses
    #expect(responses.count == 2)
    #expect(
      responses.allSatisfy {
        AtmosphericProfile(openMeteo: $0, at: Self.coordinate, for: Forecast.firstHour) != nil
      }
    )
  }

  @Test("Has no profile for a time the forecast doesn’t reach")
  func beyondForecast() throws {
    let response = try Forecast.response
    #expect(
      AtmosphericProfile(openMeteo: response, at: Self.coordinate, for: Forecast.lastInstant) != nil
    )
    #expect(
      AtmosphericProfile(
        openMeteo: response,
        at: Self.coordinate,
        for: Forecast.lastInstant.addingTimeInterval(1)
      ) == nil
    )
  }
}

struct OpenMeteoForecastWindowTests {

  private static let coordinate = CLLocationCoordinate2D(latitude: 37.75, longitude: -122.25)

  /// A profile request bounds itself with `start_hour`, which Open-Meteo rejects outright past the
  /// model's range — and a rejection would read to a pilot as a service that couldn't answer rather
  /// than a forecast that doesn't reach the day they picked.
  @Test("Answers a time past the forecast horizon without asking the service")
  func beyondForecastHorizon() async throws {
    let profiles = try await OpenMeteoService.shared.profiles(
      at: [Self.coordinate, Self.coordinate],
      for: .now.addingTimeInterval(10 * 24 * 3600)
    )

    #expect(profiles.count == 2)
    #expect(profiles.allSatisfy { $0 == nil })
  }
}

struct ConditionsMergeTests {

  /// A METAR that reports wind and pressure but, like a TAF, no temperature or dewpoint.
  private let partialReport = Conditions(
    validTime: .init(start: Forecast.firstHour, duration: 3600),
    providers: .NWS,
    windDirection: .init(value: 350, unit: .degrees),
    windSpeed: .init(value: 15, unit: .knots),
    temperature: nil,
    dewpoint: nil,
    seaLevelPressure: .init(value: 30.05, unit: .inchesOfMercury)
  )

  /// A METAR reporting variable winds: a speed, and no direction to give.
  private let variableWindReport = Conditions(
    validTime: .init(start: Forecast.firstHour, duration: 3600),
    providers: .NWS,
    windDirection: nil,
    windSpeed: .init(value: 15, unit: .knots),
    temperature: .init(value: 19, unit: .celsius),
    dewpoint: .init(value: 12, unit: .celsius),
    seaLevelPressure: .init(value: 30.05, unit: .inchesOfMercury)
  )

  /// A model forecast covering a different period, with every value reported.
  private let modelForecast = Conditions(
    validTime: .init(start: Forecast.firstHour.addingTimeInterval(-1800), duration: 3600),
    providers: .openMeteo,
    windDirection: .init(value: 100, unit: .degrees),
    windSpeed: .init(value: 3, unit: .knots),
    temperature: .init(value: 21, unit: .celsius),
    dewpoint: .init(value: 14, unit: .celsius),
    seaLevelPressure: .init(value: 29.5, unit: .inchesOfMercury)
  )

  @Test("Keeps every reported value and takes only the missing ones")
  func reportWins() {
    let merged = partialReport.filling(from: modelForecast)

    #expect(merged.windDirection == partialReport.windDirection)
    #expect(merged.windSpeed == partialReport.windSpeed)
    #expect(merged.seaLevelPressure == partialReport.seaLevelPressure)
    #expect(merged.temperature == modelForecast.temperature)
    #expect(merged.dewpoint == modelForecast.dewpoint)
  }

  @Test("Keeps the report’s own valid period and credits both services")
  func periodAndProvenance() {
    let merged = partialReport.filling(from: modelForecast)

    #expect(merged.validTime == partialReport.validTime)
    #expect(merged.source == .downloaded([.NWS, .openMeteo]))
    #expect(merged.source.providers.localizedNames == ["NWS", "Open-Meteo"])
  }

  @Test("Is complete only once nothing is left to fill")
  func completeness() {
    #expect(!partialReport.isComplete)
    #expect(partialReport.filling(from: modelForecast).isComplete)
  }

  @Test("Leaves a variable wind without a direction rather than inventing one")
  func variableWindKeepsNoDirection() {
    #expect(variableWindReport.windIsVariable)
    // Nothing is left to fill, so the lookup never reaches the model in the first place.
    #expect(variableWindReport.isComplete)

    let merged = variableWindReport.filling(from: modelForecast)
    #expect(merged.windDirection == nil)
    #expect(merged.windSpeed == variableWindReport.windSpeed)
  }

  @Test("Takes a direction for a wind that wasn’t reported at all")
  func unreportedWindIsFilled() {
    let noWindReported = Conditions(
      validTime: .init(start: Forecast.firstHour, duration: 3600),
      providers: .NWS,
      windDirection: nil,
      windSpeed: nil,
      temperature: nil,
      dewpoint: nil,
      seaLevelPressure: nil
    )
    #expect(!noWindReported.windIsVariable)

    let merged = noWindReported.filling(from: modelForecast)
    #expect(merged.windDirection == modelForecast.windDirection)
    #expect(merged.windSpeed == modelForecast.windSpeed)
  }
}
