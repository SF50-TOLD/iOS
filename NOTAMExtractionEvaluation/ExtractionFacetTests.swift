import Testing

@testable import SF50_Shared

struct ExtractionFacetTests {
  private typealias Extraction = NOTAMExtraction

  private static let dtwGold = extraction(
    effect("09R", TORA: .init(value: 6787, unit: .ft)),
    effect("09R/27L", closure: .partial, closedLength: .init(value: 1713, unit: .ft))
  )
  private static let jfkCrane = extraction(effect(nil, latitude: 40.653611, longitude: -73.825833))

  private static func effect(
    _ runway: String?,
    closure: Extraction.Closure = .none,
    closedLength: Extraction.Length? = nil,
    TORA: Extraction.Length? = nil,
    LDA: Extraction.Length? = nil,
    latitude: Double? = nil,
    longitude: Double? = nil
  ) -> Extraction.RunwayEffect {
    .init(
      runway: runway,
      closure: closure,
      closedLength: closedLength,
      closedEnd: nil,
      thresholdDisplacement: nil,
      declaredDistances: TORA == nil && LDA == nil
        ? nil : .init(TORA: TORA, TODA: nil, ASDA: nil, LDA: LDA),
      surfaceCondition: nil,
      obstacle: latitude == nil && longitude == nil
        ? nil
        : .init(
          heightAGL: nil,
          heightMSL: nil,
          distance: nil,
          distanceReference: nil,
          bearingDegrees: nil,
          latitude: latitude,
          longitude: longitude
        )
    )
  }

  private static func extraction(_ effects: Extraction.RunwayEffect...) -> Extraction {
    .init(isCanceled: false, effects: effects)
  }

  private static func score(_ name: String, expected: Extraction, actual: Extraction) throws
    -> FacetScore
  {
    try #require(ExtractionFacet.all.first { $0.name == name })
      .score(expected: expected, actual: actual)
  }

  @Test
  func `emission order does not affect the score`() throws {
    let reversed = Self.extraction(Self.dtwGold.effects[1], Self.dtwGold.effects[0])
    for name in ["TORA", "closedLength"] {
      let score = try Self.score(name, expected: Self.dtwGold, actual: reversed)
      #expect(score.readsExpected == true)
      #expect(score.isSafe == true)
    }
  }

  @Test
  func `a direction's distances folded into the pair's effect are unsafe and say where`() throws {
    let folded = Self.extraction(
      Self.effect(
        "09R/27L",
        closure: .partial,
        closedLength: .init(value: 1713, unit: .ft),
        TORA: .init(value: 6787, unit: .ft)
      )
    )
    let score = try Self.score("TORA", expected: Self.dtwGold, actual: folded)
    #expect(score.readsExpected == false)
    #expect(score.isSafe == false)
    #expect(score.rationale == "09R: missed; 09R/27L: invented")
  }

  @Test
  func `a value filed under the wrong runway fails both recall and safety`() throws {
    let misfiled = Self.extraction(Self.effect("04L", latitude: 40.653611, longitude: -73.825833))
    let score = try Self.score("obstaclePosition", expected: Self.jfkCrane, actual: misfiled)
    #expect(score.readsExpected == false)
    #expect(score.isSafe == false)
  }

  @Test
  func `a field neither side states is not scored`() throws {
    let score = try Self.score("LDA", expected: Self.dtwGold, actual: Self.dtwGold)
    #expect(score.readsExpected == nil)
    #expect(score.isSafe == nil)
  }

  @Test
  func `the same number in another unit is unsafe`() throws {
    let metres = Self.extraction(Self.effect("09R", TORA: .init(value: 6787, unit: .m)))
    let score = try Self.score("TORA", expected: Self.dtwGold, actual: metres)
    #expect(score.readsExpected == false)
    #expect(score.isSafe == false)
  }

  @Test
  func `an invented value is unsafe and a dropped one is a safe miss`() throws {
    let gold = Self.extraction(Self.effect("09R", TORA: .init(value: 6787, unit: .ft)))
    let withLDA = Self.extraction(
      Self.effect("09R", TORA: .init(value: 6787, unit: .ft), LDA: .init(value: 0, unit: .ft))
    )
    let invented = try Self.score("LDA", expected: gold, actual: withLDA)
    #expect(invented.readsExpected == nil)
    #expect(invented.isSafe == false)

    let dropped = try Self.score("TORA", expected: gold, actual: Self.extraction())
    #expect(dropped.readsExpected == false)
    #expect(dropped.isSafe == true)
  }

  @Test
  func `positions match within a ten-thousandth of a degree`() throws {
    let rounded = Self.extraction(Self.effect(nil, latitude: 40.65361, longitude: -73.82583))
    let elsewhere = Self.extraction(Self.effect(nil, latitude: 40.6541, longitude: -73.825833))
    #expect(
      try Self.score("obstaclePosition", expected: Self.jfkCrane, actual: rounded).isSafe == true
    )
    #expect(
      try Self.score("obstaclePosition", expected: Self.jfkCrane, actual: elsewhere).isSafe == false
    )
  }

  @Test
  func `half a position is never safe`() throws {
    let latitudeOnly = Self.extraction(Self.effect(nil, latitude: 40.653611))
    #expect(
      try Self.score("obstaclePosition", expected: Self.extraction(), actual: latitudeOnly).isSafe
        == false
    )
    #expect(
      try Self.score("obstaclePosition", expected: Self.jfkCrane, actual: latitudeOnly).isSafe
        == false
    )
  }

  @Test(arguments: [
    (failures: 0, trials: 90, upper: 0.0409),
    (failures: 1, trials: 300, upper: 0.0187),
    (failures: 0, trials: 0, upper: 1.0)
  ])
  func `Wilson upper bound on the failure rate`(failures: Int, trials: Int, upper: Double) {
    #expect(
      abs(FailureRateBound.wilsonUpper95(failures: failures, trials: trials) - upper) < 0.0005
    )
  }

  @Test
  func `the bound counts only passing and failing scores`() {
    let scores = [1, 1, 0, -1, 1]
    #expect(
      FailureRateBound.wilsonUpper95(scores: scores.map(Double.init))
        == FailureRateBound.wilsonUpper95(failures: 1, trials: 4)
    )
  }
}
