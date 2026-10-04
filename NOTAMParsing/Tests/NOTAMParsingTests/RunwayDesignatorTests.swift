import Testing

import NOTAMParsing

struct `Runway designator matching` {
  @Test(arguments: [("9R", "09R/27L"), ("27L", "09R/27L"), ("09", "09"), ("4", "04/22")])
  func `matches a direction the effect's runway names`(_ runwayName: String, _ effectRunway: String)
  {
    #expect(RunwayDesignator.names(runwayName, in: effectRunway))
  }

  @Test(arguments: [("9L", "09R/27L"), ("27", "09R/27L"), ("09R/27L", "09R/27L"), ("TWY A", "09")])
  func `rejects a direction the effect's runway doesn't name`(
    _ runwayName: String,
    _ effectRunway: String
  ) {
    #expect(!RunwayDesignator.names(runwayName, in: effectRunway))
  }
}
