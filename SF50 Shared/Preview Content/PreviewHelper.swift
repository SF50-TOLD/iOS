import CoreLocation
import Defaults
public import Foundation
public import SwiftData
public import WeatherKit

public final class PreviewHelper: Sendable {
  public let container: ModelContainer

  @MainActor public var mainContext: ModelContext { container.mainContext }

  public var ISA: Conditions { .init() }

  public var lightWinds: Conditions {
    .init(
      windDirection: .init(value: 280, unit: .degrees),
      windSpeed: .init(value: 12, unit: .knots),
      temperature: .init(value: 28, unit: .celsius),
      seaLevelPressure: .init(value: 30.12, unit: .inchesOfMercury)
    )
  }

  public var strongWinds: Conditions {
    .init(
      windDirection: .init(value: 90, unit: .degrees),
      windSpeed: .init(value: 28, unit: .knots),
      temperature: .init(value: 7, unit: .celsius),
      seaLevelPressure: .init(value: 29.12, unit: .inchesOfMercury)
    )
  }

  public var veryCold: Conditions {
    .init(
      windDirection: .init(value: 120, unit: .degrees),
      windSpeed: .init(value: 7, unit: .knots),
      temperature: .init(value: -56, unit: .celsius),
      seaLevelPressure: .init(value: 28.99, unit: .inchesOfMercury)
    )
  }

  public var veryHot: Conditions {
    .init(
      windDirection: .init(value: 340, unit: .degrees),
      windSpeed: .init(value: 17, unit: .knots),
      temperature: .init(value: 51, unit: .celsius),
      seaLevelPressure: .init(value: 31.17, unit: .inchesOfMercury)
    )
  }

  public var NWS: Conditions {
    // Create mock NWS conditions (calm winds, 18°C, 30.10 inHg)
    .init(
      windDirection: .init(value: 0, unit: .degrees),
      windSpeed: .init(value: 0, unit: .knots),
      temperature: .init(value: 18, unit: .celsius),
      seaLevelPressure: .init(value: 30.10, unit: .inchesOfMercury)
    )
  }

  /// Downloaded conditions credited to more than one service, as most of them are: an aviation
  /// report with its unreported values filled in from a forecast model.
  public var augmented: Conditions {
    .init(
      validTime: .init(start: .now, duration: 3600),
      providers: [.NWS, .openMeteo],
      windDirection: .init(value: 310, unit: .degrees),
      windSpeed: .init(value: 9, unit: .knots),
      temperature: .init(value: 16, unit: .celsius),
      dewpoint: .init(value: 11, unit: .celsius),
      seaLevelPressure: .init(value: 29.98, unit: .inchesOfMercury)
    )
  }

  public var METARString: String {
    "KSFO 191514Z 00000KT 10SM BKN180 18/13 A3010 RMK AO2 SLP192 T01830128 VISNO $"
  }
  public var TAFString: String {
    "KSFO 191514Z 1721/1824 VRB04KT P6SM SKC WS020/02025KT FM172200 31008KT P6SM SKC FM180100 28013KT P6SM FEW200 FM180800 28006KT P6SM FEW200 FM181000 VRB05KT P6SM SKC WS020/02030KT FM181500 36008KT P6SM SKC WS015/03030KT FM182000 36012KT P6SM SKC WS015/03035KT"
  }
  public var hourWeather: HourWeather {
    get async throws {
      try await WeatherService().weather(for: .init(latitude: 37, longitude: -121)).hourlyForecast
        .first!
    }
  }

  public init() throws {
    container = try .init(
      for: Airport.self,
      Runway.self,
      NOTAM.self,
      Scenario.self,
      Cycle.self,
      Obstacle.self,
      Procedure.self,
      ProcedureSegment.self,
      Leg.self,
      configurations: .init(isStoredInMemoryOnly: true)
    )
  }

  @MainActor
  public func reset() throws {
    Defaults.removeAll(suite: .init(suiteName: "group.codes.tim.TOLD")!)

    try mainContext.delete(model: Leg.self)
    try mainContext.delete(model: Procedure.self)
    try mainContext.delete(model: ProcedureSegment.self)
    try mainContext.delete(model: Obstacle.self)
    try mainContext.delete(model: Runway.self)
    try mainContext.delete(model: Airport.self)
    try mainContext.delete(model: NOTAM.self)
    try mainContext.delete(model: Scenario.self)
    try mainContext.delete(model: Cycle.self)
    try mainContext.save()
  }

  @MainActor
  public func useMetricUnits() {
    Defaults[.fuelVolumeUnit] = .liters
    Defaults[.heightUnit] = .meters
    Defaults[.speedUnit] = .kilometersPerHour
    Defaults[.temperatureUnit] = .celsius
  }

  @MainActor
  public func insert(airport builder: AirportBuilder) throws {
    let (airport, runways) = builder.build()
    mainContext.insert(airport)
    for runway in runways {
      mainContext.insert(runway)
    }
    try mainContext.save()
  }

  @MainActor
  public func insertBasicScenarios() throws {
    // Takeoff scenarios
    let takeoffScenarios = [
      Scenario(
        name: "OAT +10°C",
        operation: .takeoff,
        deltaTemperature: .init(value: 10, unit: .celsius)
      ),
      Scenario(
        name: "OAT -10°C",
        operation: .takeoff,
        deltaTemperature: .init(value: -10, unit: .celsius)
      ),
      Scenario(
        name: "Wind Speed +10 kts",
        operation: .takeoff,
        deltaWindSpeed: .init(value: 10, unit: .knots)
      ),
      Scenario(
        name: "Weight +200 lbs",
        operation: .takeoff,
        deltaWeight: .init(value: 200, unit: .pounds)
      )
    ]

    // Landing scenarios
    let landingScenarios = [
      Scenario(
        name: "OAT +10°C",
        operation: .landing,
        deltaTemperature: .init(value: 10, unit: .celsius)
      ),
      Scenario(
        name: "Flaps 50",
        operation: .landing,
        flapSettingOverride: "flaps50"
      ),
      Scenario(
        name: "Water/Slush 0.5″",
        operation: .landing,
        contaminationOverride: "waterOrSlush",
        contaminationDepth: .init(value: 0.5, unit: .inches)
      ),
      Scenario(
        name: "Dry Snow",
        operation: .landing,
        contaminationOverride: "drySnow"
      )
    ]

    for scenario in takeoffScenarios + landingScenarios {
      mainContext.insert(scenario)
    }
    try mainContext.save()
  }

  @MainActor
  public func load(locationID: String) throws -> Airport? {
    let predicate = #Predicate<Airport> { $0.locationID == locationID }
    var descriptor = FetchDescriptor(predicate: predicate)
    descriptor.fetchLimit = 1
    return try mainContext.fetch(descriptor).first
  }

  @MainActor
  public func load(airportID: String, runway: String) throws -> Runway? {
    guard let airport = try load(locationID: airportID) else { return nil }
    let airportID = airport.persistentModelID
    let predicate = #Predicate<Runway> {
      $0.airport.persistentModelID == airportID && $0.name == runway
    }
    var descriptor = FetchDescriptor(predicate: predicate)
    descriptor.fetchLimit = 1
    return try mainContext.fetch(descriptor).first
  }

  @MainActor
  @discardableResult
  public func addNOTAM(
    to runway: Runway,
    shortenTakeoff: Double? = nil,
    shortenLanding: Double? = nil,
    contamination: Contamination? = nil,
    obstacleHeight: Double? = nil,
    obstacleDistance: Double? = nil
  ) throws -> NOTAM {
    let notam = NOTAM(
      runway: runway,
      contamination: contamination,
      takeoffDistanceShortening: shortenTakeoff.map { .init(value: $0, unit: .feet) },
      landingDistanceShortening: shortenLanding.map { .init(value: $0, unit: .feet) },
      obstacleHeight: obstacleHeight.map { .init(value: $0, unit: .feet) },
      obstacleDistance: obstacleDistance.map { .init(value: $0, unit: .nauticalMiles) }
    )
    runway.notam = notam
    mainContext.insert(notam)
    try mainContext.save()
    return notam
  }

  @MainActor
  public func insertCycle(
    _ dataSource: CycleDataSource,
    name: String,
    effective: Date = Date().addingTimeInterval(-7 * 24 * 60 * 60),
    expires: Date = Date().addingTimeInterval(21 * 24 * 60 * 60)
  ) {
    mainContext.insert(
      Cycle(
        dataSource: dataSource,
        name: name,
        effective: effective,
        expires: expires
      )
    )
  }

  @MainActor
  public func insertCurrentCycle(_ dataSource: CycleDataSource, name: String) {
    insertCycle(
      dataSource,
      name: name,
      effective: Date().addingTimeInterval(-7 * 24 * 60 * 60),
      expires: Date().addingTimeInterval(21 * 24 * 60 * 60)
    )
  }

  @MainActor
  public func insertExpiredCycle(_ dataSource: CycleDataSource, name: String) {
    insertCycle(
      dataSource,
      name: name,
      effective: Date().addingTimeInterval(-35 * 24 * 60 * 60),
      expires: Date().addingTimeInterval(-7 * 24 * 60 * 60)
    )
  }

  @MainActor
  public func insertFutureCycle(_ dataSource: CycleDataSource, name: String) {
    insertCycle(
      dataSource,
      name: name,
      effective: Date().addingTimeInterval(14 * 24 * 60 * 60),
      expires: Date().addingTimeInterval(70 * 24 * 60 * 60)
    )
  }

  @MainActor
  public func setUpToDate() {
    Defaults[.schemaVersion] = latestSchemaVersion
    // Set expiration date 28 days in the future
    let effectiveDate = Date()
    let expirationDate = effectiveDate.addingTimeInterval(28 * 24 * 60 * 60)
    try? mainContext.delete(model: Cycle.self)
    mainContext.insert(
      Cycle(
        dataSource: .nasr,
        name: "Preview",
        effective: effectiveDate,
        expires: expirationDate
      )
    )
    try? mainContext.save()
  }

  @MainActor
  public func setOutOfDate() {
    Defaults[.schemaVersion] = latestSchemaVersion
    // Set expiration date in the past
    let effectiveDate = Date().addingTimeInterval(-29 * 24 * 60 * 60)
    let expirationDate = Date().addingTimeInterval(-1)
    try? mainContext.delete(model: Cycle.self)
    mainContext.insert(
      Cycle(
        dataSource: .nasr,
        name: "Expired",
        effective: effectiveDate,
        expires: expirationDate
      )
    )
    try? mainContext.save()
  }

  public func setTakeoff(runway: Runway) {
    Defaults[.payload] = .init(value: 400, unit: .pounds)
    Defaults[.takeoffFuel] = .init(value: 220, unit: .gallons)
    Defaults[.takeoffAirport] = runway.airport.recordID
    Defaults[.takeoffRunway] = runway.name
  }

  public func setLanding(runway: Runway) {
    Defaults[.payload] = .init(value: 400, unit: .pounds)
    Defaults[.landingFuel] = .init(value: 70, unit: .gallons)
    Defaults[.landingAirport] = runway.airport.recordID
    Defaults[.landingRunway] = runway.name
  }

  public func newBackgroundContext() -> ModelContext { .init(container) }
}

@MainActor
public struct AirportBuilder {
  private let makeAirport: @MainActor () -> Airport
  private let makeRunways: @MainActor (Airport) -> [Runway]

  public init(
    airport: @escaping @MainActor @autoclosure () -> Airport,
    runways: @escaping @MainActor (Airport) -> [Runway]
  ) {
    self.makeAirport = airport
    self.makeRunways = runways
  }

  /// Creates fresh Airport and Runway instances (not yet inserted into any context).
  public func build() -> (airport: Airport, runways: [Runway]) {
    let airport = makeAirport()
    let runways = makeRunways(airport)
    airport.runways = runways
    return (airport, runways)
  }

  public func unsaved() -> Airport {
    build().airport
  }
}
