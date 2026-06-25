import Defaults
import Foundation
import SF50_Shared
import SwiftData

enum UITestingHelper {
  static var weatherLoader: (any WeatherLoaderProtocol)? {
    guard ProcessInfo.processInfo.arguments.contains("UI-TESTING") else { return nil }
    return UITestingWeatherLoader()
  }

  static var notamLoader: (any NOTAMLoaderProtocol)? {
    guard ProcessInfo.processInfo.arguments.contains("UI-TESTING") else { return nil }
    return UITestingNOTAMLoader()
  }

  static func setupUITestingEnvironment(container: ModelContainer) {
    // Reset all defaults
    Defaults.removeAll(suite: UserDefaults(suiteName: "group.codes.tim.TOLD")!)

    // Check if we're generating screenshots (should use live data)
    let isGeneratingScreenshots = ProcessInfo.processInfo.arguments.contains("GENERATE-SCREENSHOTS")

    // Set minimal configuration for testing - let tests go through setup flow
    Defaults[.schemaVersion] = latestSchemaVersion
    Defaults[.favoriteAirports] = []  // Ensure no favorites at start

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

    // Set expiration date 28 days in the future to prevent database loader from appearing
    let effectiveDate = Date()
    let expirationDate = effectiveDate.addingTimeInterval(28 * 24 * 60 * 60)
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
