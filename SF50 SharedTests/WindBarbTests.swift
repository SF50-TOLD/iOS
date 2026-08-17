import Foundation
import Testing

@testable import SF50_Shared

struct WindBarbFeatherTests {

  @Test(
    "Draws the feathers a station model would, rounding to the nearest five knots",
    arguments: [
      // speed, pennants, full barbs, half barb
      (0.0, 0, 0, false),
      (2.0, 0, 0, false),
      (3.0, 0, 0, true),
      (5.0, 0, 0, true),
      (10.0, 0, 1, false),
      (12.0, 0, 1, false),
      (13.0, 0, 1, true),
      (25.0, 0, 2, true),
      (47.0, 0, 4, true),
      (50.0, 1, 0, false),
      (55.0, 1, 0, true),
      (105.0, 2, 0, true)
    ] as [(Double, Int, Int, Bool)]
  )
  func feathers(speedKts: Double, pennants: Int, full: Int, half: Bool) {
    let feathers = WindBarb.Feathers(componentKts: speedKts)

    #expect(feathers.pennants == pennants)
    #expect(feathers.full == full)
    #expect(feathers.half == half)
  }

  @Test("Reads a headwind the same as the tailwind of the same strength")
  func signIgnored() {
    #expect(WindBarb.Feathers(componentKts: -37) == WindBarb.Feathers(componentKts: 37))
  }

  @Test("Calls anything rounding to nothing calm")
  func calmBelowFiveKnots() {
    #expect(WindBarb.Feathers(componentKts: 0).isCalm)
    #expect(WindBarb.Feathers(componentKts: 2.4).isCalm)
    #expect(!WindBarb.Feathers(componentKts: 2.5).isCalm)
    #expect(!WindBarb.Feathers(componentKts: -8).isCalm)
  }
}
