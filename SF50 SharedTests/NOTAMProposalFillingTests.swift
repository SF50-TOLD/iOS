import Foundation
import Testing

@testable import SF50_Shared

/// Filling the NOTAM editor in from one downloaded NOTAM writes only what that NOTAM proposes for
/// the operation, leaves the pilot's other entries alone, and can be undone.
struct `NOTAM proposal filling` {
  /// A1 proposes RwyCC 3; A2 an obstacle 170 ft high, 0.4 NM beyond the departure end.
  private static var proposal: NOTAMProposal {
    var proposal = NOTAMProposal()
    proposal.contamination = [.init(.rwyCC(3), from: "A1")]
    proposal.obstacle = [
      .init(.init(height: feet(170), distance: .init(value: 0.4, unit: .nauticalMiles)), from: "A2")
    ]
    return proposal
  }

  private static func runway() -> Runway {
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
      takeoffDistance: .init(value: 5000, unit: .feet),
      landingDistance: .init(value: 5000, unit: .feet),
      surfaceType: .paved,
      airport: airport
    )
  }

  private static func feet(_ value: Double) -> Measurement<UnitLength> {
    .init(value: value, unit: .feet)
  }

  @Test
  func `fills only what the chosen NOTAM proposes for the operation`() {
    let notam = NOTAM(
      runway: Self.runway(),
      obstacleHeight: Self.feet(50),
      obstacleDistance: .init(value: 0.5, unit: .nauticalMiles)
    )

    Self.proposal.from(notamID: "A1").fill(notam, for: .takeoff)
    #expect(notam.obstacleHeight.converted(to: .feet).value.rounded() == 50)
    #expect(notam.contamination == nil)

    let restoration = Self.proposal.from(notamID: "A2").fill(notam, for: .takeoff)
    #expect(notam.obstacleHeight.converted(to: .feet).value.rounded() == 170)
    #expect((notam.obstacleDistance.converted(to: .nauticalMiles).value * 10).rounded() == 4)
    #expect(Self.proposal.from(notamID: "A2").fields(for: .landing).isEmpty)

    restoration.restore(notam)
    #expect(notam.obstacleHeight.converted(to: .feet).value.rounded() == 50)
    #expect((notam.obstacleDistance.converted(to: .nauticalMiles).value * 10).rounded() == 5)
  }

  @Test
  func `undoes a fill, putting back what the pilot entered`() {
    let notam = NOTAM(runway: Self.runway(), contamination: .wetRunway)

    let restoration = Self.proposal.from(notamID: "A1").fill(notam, for: .landing)
    #expect(notam.contamination == .rwyCC(3))

    restoration.restore(notam)
    #expect(notam.contamination == .wetRunway)
  }
}
