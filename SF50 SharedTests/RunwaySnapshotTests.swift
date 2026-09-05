import Foundation
import Testing

@testable import SF50_Shared

/// The widget and the App Intents surfaces measure against a snapshot rather than the SwiftData
/// runway, so the snapshot has to carry the same distances the app's own screens compare against —
/// NOTAM shortening included, and the run kept distinct from the distance.
@Suite
struct `Runway Snapshot Distances` {
  /// 5,000 ft of pavement with a 1,000 ft clearway: TORA 5,000, TODA 6,000.
  private static func runwayWithClearway() -> Runway {
    let airport = Airport(
      recordID: "TEST",
      locationID: "TEST",
      ICAO_ID: nil,
      name: "Test Airport",
      city: nil,
      dataSource: .NASR,
      latitude: .init(value: 0, unit: .degrees),
      longitude: .init(value: 0, unit: .degrees),
      elevation: .init(value: 0, unit: .feet),
      variation: .init(value: 0, unit: .degrees)
    )
    return Runway(
      name: "36",
      elevation: nil,
      trueHeading: .init(value: 360, unit: .degrees),
      gradient: 0,
      length: .init(value: 5000, unit: .feet),
      takeoffRun: .init(value: 5000, unit: .feet),
      takeoffDistance: .init(value: 6000, unit: .feet),
      landingDistance: .init(value: 4800, unit: .feet),
      surfaceType: .paved,
      airport: airport
    )
  }

  /// Comparing `Measurement` values directly compares metres, where a foot-denominated subtraction
  /// leaves float dust.
  private static func feet(_ distance: Measurement<UnitLength>) -> Double {
    (distance.converted(to: .feet).value * 100).rounded() / 100
  }

  @Test("the ground run is measured against the run, not the distance over the clearway")
  func runAndDistanceAreDistinct() {
    let snapshot = RunwaySnapshot(from: Self.runwayWithClearway())

    #expect(Self.feet(snapshot.availableRun(for: .takeoff)) == 5000)
    #expect(Self.feet(snapshot.availableDistance(for: .takeoff)) == 6000)
  }

  @Test("a NOTAM shortening the runway shortens what the snapshot reports as available")
  func NOTAMShorteningIsCarried() {
    let runway = Self.runwayWithClearway()
    runway.notam = NOTAM(
      runway: runway,
      takeoffDistanceShortening: .init(value: 1000, unit: .feet),
      landingDistanceShortening: .init(value: 800, unit: .feet)
    )
    let snapshot = RunwaySnapshot(from: runway)

    #expect(Self.feet(snapshot.availableRun(for: .takeoff)) == 4000)
    #expect(Self.feet(snapshot.availableDistance(for: .takeoff)) == 5000)
    #expect(Self.feet(snapshot.availableDistance(for: .landing)) == 4000)
  }

  @Test("a landing measures both its run and its distance against the landing distance available")
  func landingUsesOneDenominator() {
    let snapshot = RunwaySnapshot(from: Self.runwayWithClearway())

    #expect(snapshot.availableRun(for: .landing) == snapshot.availableDistance(for: .landing))
  }
}
