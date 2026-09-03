import CoreLocation
import Defaults
import Foundation
import SF50_Shared
import SwiftData

enum UITestingHelper {
  static var isUITesting: Bool {
    ProcessInfo.processInfo.arguments.contains("UI-TESTING")
  }

  static var isGeneratingScreenshots: Bool {
    ProcessInfo.processInfo.arguments.contains("GENERATE-SCREENSHOTS")
  }

  static var weatherLoader: (any WeatherLoaderProtocol)? {
    guard ProcessInfo.processInfo.arguments.contains("UI-TESTING") else { return nil }
    return UITestingWeatherLoader()
  }

  static var notamLoader: (any NOTAMLoaderProtocol)? {
    guard ProcessInfo.processInfo.arguments.contains("UI-TESTING") else { return nil }
    return UITestingNOTAMLoader()
  }

  /// The atmosphere loader the terrain profile's weather layers should use.
  ///
  /// Unlike the other loaders this is never `nil`: the environment needs something to hold, so the
  /// real loader stands in outside of UI testing.
  static var pathAtmosphereLoader: any PathAtmosphereLoading {
    guard ProcessInfo.processInfo.arguments.contains("UI-TESTING") else {
      return PathAtmosphereLoader.shared
    }
    return UITestingPathAtmosphereLoader()
  }

  /// The location source the nearest-airport picker should use.
  ///
  /// `nil` outside UI testing, and `nil` under UI testing unless a test scripts a fix or a
  /// refusal. Nothing is injected in those cases, and the environment default builds its real
  /// Core Location source only when something first reads it — so a test that never opens the
  /// picker never starts location updates, and never raises a permission prompt.
  @MainActor static var locationStreamer: (any LocationStreamer)? {
    guard isUITesting else { return nil }
    if ProcessInfo.processInfo.arguments.contains("LOCATION-DENIED") {
      return MockLocationStreamer(availability: .authorizationDenied)
    }
    guard let location = seededLocation() else { return nil }
    return MockLocationStreamer(location: location)
  }

  static func setupUITestingEnvironment(container: ModelContainer) {
    // Reset all defaults
    Defaults.removeAll(suite: UserDefaults(suiteName: "group.codes.tim.TOLD")!)

    // Check if we're generating screenshots (should use live data)
    let isGeneratingScreenshots = ProcessInfo.processInfo.arguments.contains("GENERATE-SCREENSHOTS")

    // Set minimal configuration for testing - let tests go through setup flow
    Defaults[.schemaVersion] = latestSchemaVersion
    Defaults[.favoriteAirports] = seededFavoriteAirports()

    if ProcessInfo.processInfo.arguments.contains("USE-REGRESSION-MODEL") {
      Defaults[.useRegressionModel] = true
    }

    if ProcessInfo.processInfo.arguments.contains("SKIP-SCENARIO-SEEDING") {
      Defaults[.defaultScenariosSeeded] = true
    }

    // Only seed test data for regular UI tests, not screenshot generation
    if !isGeneratingScreenshots {
      // Seed test data for airports used in UI tests
      Task { @MainActor in
        seedTestData(container: container)
      }
    }
  }

  /// Favorite airports requested via the `FAVORITE-AIRPORTS=ID1,ID2` launch
  /// argument, so a test can open the picker straight to a seeded favorite
  /// without driving the search field. Empty when the argument is absent.
  private static func seededFavoriteAirports() -> Set<String> {
    let prefix = "FAVORITE-AIRPORTS="
    guard let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix(prefix) })
    else { return [] }
    return Set(argument.dropFirst(prefix.count).split(separator: ",").map(String.init))
  }

  /// The fix a test scripted with `LOCATION=<latitude>,<longitude>`, if any.
  private static func seededLocation() -> CLLocation? {
    let prefix = "LOCATION="
    guard let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix(prefix) })
    else { return nil }
    let coordinates = argument.dropFirst(prefix.count).split(separator: ",")
    guard coordinates.count == 2,
      let latitude = Double(coordinates[0]),
      let longitude = Double(coordinates[1])
    else { return nil }
    return .init(latitude: latitude, longitude: longitude)
  }

  @MainActor
  private static func seedTestData(container: ModelContainer) {
    let context = container.mainContext

    // Delete existing data
    try? context.delete(model: Leg.self)
    try? context.delete(model: ProcedureSegment.self)
    try? context.delete(model: Procedure.self)
    try? context.delete(model: Obstacle.self)
    try? context.delete(model: Runway.self)
    try? context.delete(model: Airport.self)
    try? context.delete(model: NOTAM.self)
    try? context.delete(model: Scenario.self)
    try? context.delete(model: Cycle.self)

    // Insert test airports
    try? insertAirport(.KOAK, context: context)
    try? insertAirport(.KSQL, context: context)
    try? insertAirport(.K1C9, context: context)

    // Expire the cycles 1 day in the past when the test forces stale nav data so
    // the loading consent screen gates the app; otherwise set expiration 28 days
    // in the future to keep the database loader from appearing.
    let effectiveDate = Date()
    let forceStale = ProcessInfo.processInfo.arguments.contains("STALE-NAV-DATA")
    let expirationInterval: TimeInterval = forceStale ? -24 * 60 * 60 : 28 * 24 * 60 * 60
    let expirationDate = effectiveDate.addingTimeInterval(expirationInterval)
    context.insert(
      Cycle(
        dataSource: .nasr,
        name: "UITest",
        effective: effectiveDate,
        expires: expirationDate
      )
    )
    context.insert(
      Cycle(
        dataSource: .cifp,
        name: "UITest",
        effective: effectiveDate,
        expires: expirationDate
      )
    )
    context.insert(
      Cycle(
        dataSource: .dof,
        name: "UITest",
        effective: effectiveDate,
        expires: expirationDate
      )
    )

    seedProcedureData(context: context)

    try? context.save()
  }

  @MainActor
  private static func insertAirport(_ builder: AirportBuilder, context: ModelContext) throws {
    let airport = builder.unsaved()
    context.insert(airport)
    for runway in airport.runways {
      context.insert(runway)
    }
  }

  @MainActor
  private static func seedProcedureData(context: ModelContext) {
    // Fetch the OAK airport that was just inserted
    var descriptor = FetchDescriptor<Airport>(
      predicate: #Predicate { $0.locationID == "OAK" }
    )
    descriptor.fetchLimit = 1
    guard let airport = try? context.fetch(descriptor).first else { return }

    // MARK: SID departure for runway 28R

    let sid = Procedure(
      type: .departure,
      identifier: "OAKSI2",
      airport: airport
    )
    context.insert(sid)

    let sidRunwaySegment = ProcedureSegment(
      runwayNames: ["28R"],
      procedure: sid
    )
    context.insert(sidRunwaySegment)

    let sidLeg1 = Leg(
      identifier: "OAKSI",
      latitude: .init(value: 37.7213, unit: .degrees),
      longitude: .init(value: -122.2212, unit: .degrees),
      legType: .initialFix,
      sequenceIndex: 0,
      segment: sidRunwaySegment
    )
    context.insert(sidLeg1)

    let sidLeg2 = Leg(
      identifier: "REBAS",
      latitude: .init(value: 37.75, unit: .degrees),
      longitude: .init(value: -122.30, unit: .degrees),
      altitudeRestriction: .atOrAbove(.init(value: 800, unit: .feet)),
      legType: .trackToFix(course: .init(value: 292, unit: .degrees)),
      sequenceIndex: 1,
      segment: sidRunwaySegment
    )
    context.insert(sidLeg2)

    let sidCommonSegment = ProcedureSegment(
      runwayNames: [],
      procedure: sid
    )
    context.insert(sidCommonSegment)

    let sidLeg3 = Leg(
      identifier: "ORCKA",
      latitude: .init(value: 37.80, unit: .degrees),
      longitude: .init(value: -122.40, unit: .degrees),
      altitudeRestriction: .atOrAbove(.init(value: 3000, unit: .feet)),
      legType: .trackToFix(course: .init(value: 292, unit: .degrees)),
      sequenceIndex: 2,
      segment: sidCommonSegment
    )
    context.insert(sidLeg3)

    let sidLeg4 = Leg(
      identifier: nil,
      latitude: nil,
      longitude: nil,
      altitudeRestriction: .atOrAbove(.init(value: 5000, unit: .feet)),
      legType: .courseToAltitude(course: .init(value: 292, unit: .degrees)),
      sequenceIndex: 3,
      segment: sidCommonSegment
    )
    context.insert(sidLeg4)

    // MARK: Approach with missed approach for runway 28R

    let approach = Procedure(
      type: .approach,
      identifier: "I28R",
      name: "ILS RWY 28R",
      runwayName: "28R",
      airport: airport
    )
    context.insert(approach)

    // Missed approach segment (empty runwayNames)
    let missedSegment = ProcedureSegment(
      runwayNames: [],
      procedure: approach
    )
    context.insert(missedSegment)

    let missedLeg1 = Leg(
      identifier: "RW28R",
      latitude: .init(value: 37.72481, unit: .degrees),
      longitude: .init(value: -122.20470, unit: .degrees),
      legType: .initialFix,
      sequenceIndex: 0,
      segment: missedSegment
    )
    context.insert(missedLeg1)

    let missedLeg2 = Leg(
      identifier: "MINOK",
      latitude: .init(value: 37.74, unit: .degrees),
      longitude: .init(value: -122.26, unit: .degrees),
      altitudeRestriction: .atOrAbove(.init(value: 600, unit: .feet)),
      legType: .trackToFix(course: .init(value: 292, unit: .degrees)),
      sequenceIndex: 1,
      segment: missedSegment
    )
    context.insert(missedLeg2)

    let missedLeg3 = Leg(
      identifier: "FITKI",
      latitude: .init(value: 37.76, unit: .degrees),
      longitude: .init(value: -122.32, unit: .degrees),
      altitudeRestriction: .atOrAbove(.init(value: 2000, unit: .feet)),
      legType: .trackToFix(course: .init(value: 292, unit: .degrees)),
      sequenceIndex: 2,
      segment: missedSegment
    )
    context.insert(missedLeg3)

    let missedLeg4 = Leg(
      identifier: nil,
      latitude: nil,
      longitude: nil,
      altitudeRestriction: .atOrAbove(.init(value: 4000, unit: .feet)),
      legType: .courseToAltitude(course: .init(value: 292, unit: .degrees)),
      sequenceIndex: 3,
      segment: missedSegment
    )
    context.insert(missedLeg4)

    // MARK: Obstacle in the departure corridor

    let obstacle = Obstacle(
      heightMSL: .init(value: 300, unit: .feet),
      latitude: .init(value: 37.75, unit: .degrees),
      longitude: .init(value: -122.28, unit: .degrees)
    )
    context.insert(obstacle)
  }
}
