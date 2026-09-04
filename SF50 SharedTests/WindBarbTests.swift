import Foundation
import Testing

@testable import SF50_Shared

struct WindBarbFeatherTests {

  @Test(
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
  func `draws the feathers a station model would, rounding to the nearest five knots`(
    speedKts: Double,
    pennants: Int,
    full: Int,
    half: Bool
  ) {
    let feathers = WindBarb.Feathers(componentKts: speedKts)

    #expect(feathers.pennants == pennants)
    #expect(feathers.full == full)
    #expect(feathers.half == half)
  }

  @Test
  func `reads a headwind the same as the tailwind of the same strength`() {
    #expect(WindBarb.Feathers(componentKts: -37) == WindBarb.Feathers(componentKts: 37))
  }

  @Test
  func `calls anything rounding to nothing calm`() {
    #expect(WindBarb.Feathers(componentKts: 0).isCalm)
    #expect(WindBarb.Feathers(componentKts: 2.4).isCalm)
    #expect(!WindBarb.Feathers(componentKts: 2.5).isCalm)
    #expect(!WindBarb.Feathers(componentKts: -8).isCalm)
  }
}
