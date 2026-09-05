import Defaults
import MeasurementKit
import SF50_Shared
import SwiftUI
import WidgetKit

/// Sample timeline entries for the widget previews.
///
/// `PreviewView` cannot be used inside a timeline closure, so these build entries from unsaved airport
/// fixtures and literal numbers rather than from a model container.
@MainActor
enum PreviewEntries {
  static func airportWithPerformance() -> RunwayWidgetEntry {
    entry(
      airport: AirportBuilder.KSQL.unsaved(),
      conditions: .init(
        windDirection: .init(value: 280, unit: .degrees),
        windSpeed: .init(value: 10, unit: .knots),
        temperature: standardTemperature,
        seaLevelPressure: standardSeaLevelPressure
      ),
      operation: .takeoff,
      results: ["30": takeoff(distanceFt: 2500), "12": takeoff(distanceFt: 2800)]
    )
  }

  static func oakAirportWithPerformance() -> RunwayWidgetEntry {
    entry(
      airport: AirportBuilder.KOAK.unsaved(),
      conditions: .init(
        windDirection: .init(value: 90, unit: .degrees),
        windSpeed: .init(value: 28, unit: .knots),
        temperature: .init(value: 7, unit: .celsius),
        seaLevelPressure: .init(value: 29.12, unit: .inchesOfMercury)
      ),
      operation: .takeoff,
      results: [
        "12": takeoff(distanceFt: 3500),
        "30": takeoff(distanceFt: 2900),
        "10L": takeoff(distanceFt: 4200),
        "28R": takeoff(distanceFt: 2600)
      ]
    )
  }

  static func oakAirportLanding() -> RunwayWidgetEntry {
    entry(
      airport: AirportBuilder.KOAK.unsaved(),
      conditions: .init(
        windDirection: .init(value: 300, unit: .degrees),
        windSpeed: .init(value: 12, unit: .knots),
        temperature: .init(value: 14, unit: .celsius),
        seaLevelPressure: standardSeaLevelPressure
      ),
      operation: .landing,
      results: [
        "12": landing(distanceFt: 2400, VREFKts: 88),
        "30": landing(distanceFt: 2400, VREFKts: 88),
        "10L": landing(distanceFt: 2450, VREFKts: 88),
        "28R": landing(distanceFt: 2450, VREFKts: 88)
      ]
    )
  }

  static func airportWithInsufficientDistance() -> RunwayWidgetEntry {
    entry(
      airport: AirportBuilder.KSQL.unsaved(),
      conditions: .init(
        windDirection: .init(value: 0, unit: .degrees),
        windSpeed: .init(value: 5, unit: .knots),
        temperature: .init(value: 35, unit: .celsius),
        seaLevelPressure: .init(value: 29.50, unit: .inchesOfMercury)
      ),
      operation: .takeoff,
      results: [
        "30": takeoff(distanceFt: 3500),
        "12": .init(groundRun: .notAuthorized, distance: .notAuthorized)
      ]
    )
  }
}

extension PreviewEntries {
  private static func takeoff(distanceFt: Double) -> RunwayPerformance {
    .init(
      groundRun: .value(.init(value: distanceFt * 0.7, unit: .feet)),
      distance: .value(.init(value: distanceFt, unit: .feet)),
      climbGradient: .value(.init(value: 500, unit: UnitSlope.feetPerNauticalMile))
    )
  }

  private static func landing(distanceFt: Double, VREFKts: Double) -> RunwayPerformance {
    .init(
      groundRun: .value(.init(value: distanceFt * 0.6, unit: .feet)),
      distance: .value(.init(value: distanceFt, unit: .feet)),
      VREF: .value(.init(value: VREFKts, unit: .knots))
    )
  }

  private static func entry(
    airport: Airport,
    conditions: Conditions,
    operation: SF50_Shared.Operation,
    results: [String: RunwayPerformance]
  ) -> RunwayWidgetEntry {
    .init(
      date: Date(),
      performance: .init(
        airportRecordID: airport.recordID,
        airportName: airport.name,
        airportDisplayID: airport.displayID,
        operation: operation,
        runways: airport.runways.map(RunwaySnapshot.init(from:)),
        conditions: conditions,
        results: results
      )
    )
  }
}

#Preview("Small Widget - No Airport", as: .systemSmall) {
  SelectedAirportPerformanceWidget()
} timeline: {
  RunwayWidgetEntry.empty()
}

#Preview("Small Widget - With Airport", as: .systemSmall) {
  SelectedAirportPerformanceWidget()
} timeline: {
  PreviewEntries.airportWithPerformance()
}

#Preview("Small Widget - Insufficient Distance", as: .systemSmall) {
  SelectedAirportPerformanceWidget()
} timeline: {
  PreviewEntries.airportWithInsufficientDistance()
}

#Preview("Medium Widget - No Airport", as: .systemMedium) {
  SelectedAirportPerformanceWidget()
} timeline: {
  RunwayWidgetEntry.empty()
}

#Preview("Medium Widget - Takeoff", as: .systemMedium) {
  SelectedAirportPerformanceWidget()
} timeline: {
  PreviewEntries.oakAirportWithPerformance()
}

#Preview("Medium Widget - Landing", as: .systemMedium) {
  SelectedAirportPerformanceWidget()
} timeline: {
  PreviewEntries.oakAirportLanding()
}

#Preview("Medium Widget - Mixed Status", as: .systemMedium) {
  SelectedAirportPerformanceWidget()
} timeline: {
  PreviewEntries.airportWithInsufficientDistance()
}
