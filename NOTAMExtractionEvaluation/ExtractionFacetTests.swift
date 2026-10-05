import NOTAMModel
import Testing

@testable import SF50_Shared

struct ExtractionFacetTests {
  private typealias Extraction = NOTAMExtraction

  private static let closedPortion = Extraction.PartialClosure(
    length: .init(value: 1713, unit: .ft),
    end: "W"
  )
  private static let dtwGold = extraction(
    effect("09R", partialClosure: closedPortion, TORA: .init(value: 6787, unit: .ft)),
    effect("27L", partialClosure: closedPortion)
  )
  private static let craneOffRunway27 = extraction(
    obstacles: [crane(height: 185, reference: .init(kind: .departureEnd, runway: "27"))]
  )

  private static func effect(
    _ runway: String?,
    partialClosure: Extraction.PartialClosure? = nil,
    TORA: Extraction.Length? = nil,
    LDA: Extraction.Length? = nil,
    contaminants: [Extraction.Contaminant]? = nil
  ) -> Extraction.RunwayEffect {
    .init(
      runway: runway,
      closure: .none,
      partialClosure: partialClosure,
      declaredDistances: TORA == nil && LDA == nil ? nil : .init(TORA: TORA, LDA: LDA),
      surfaceCondition: contaminants.map { .init(rwyCC: nil, contaminants: $0) }
    )
  }

  private static func crane(height: Double, reference: Extraction.ObstacleReference)
    -> Extraction.Obstacle
  {
    .init(
      height: .init(value: height, unit: .ft, datum: .MSL),
      distance: .init(value: 0.4, unit: .nm),
      reference: reference,
      direction: .compass(.NW)
    )
  }

  private static func extraction(
    _ effects: Extraction.RunwayEffect...,
    obstacles: [Extraction.Obstacle] = []
  ) -> Extraction {
    .init(isCanceled: false, effects: effects, obstacles: obstacles)
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
    for name in ["TORA", "closedLength", "closedEnd"] {
      let score = try Self.score(name, expected: Self.dtwGold, actual: reversed)
      #expect(score.readsExpected == true)
      #expect(score.isSafe == true)
    }
  }

  @Test
  func `a value filed under the other direction is unsafe and says where`() throws {
    let misfiled = Self.extraction(
      Self.effect("09R", partialClosure: Self.closedPortion),
      Self.effect("27L", partialClosure: Self.closedPortion, TORA: .init(value: 6787, unit: .ft))
    )
    let score = try Self.score("TORA", expected: Self.dtwGold, actual: misfiled)
    #expect(score.readsExpected == false)
    #expect(score.isSafe == false)
    #expect(score.rationale == "09R: missed; 27L: invented")
  }

  @Test
  func `an obstacle measured from the wrong runway end fails both recall and safety`() throws {
    let misfiled = Self.extraction(
      obstacles: [Self.crane(height: 185, reference: .init(kind: .departureEnd, runway: "09"))]
    )
    let score = try Self.score("obstacleHeight", expected: Self.craneOffRunway27, actual: misfiled)
    #expect(score.readsExpected == false)
    #expect(score.isSafe == false)
  }

  @Test
  func `an obstacle's distance from another kind of reference is wrong`() throws {
    let fromThreshold = Self.extraction(
      obstacles: [Self.crane(height: 185, reference: .init(kind: .threshold, runway: "27"))]
    )
    let score = try Self.score(
      "obstacleDistance",
      expected: Self.craneOffRunway27,
      actual: fromThreshold
    )
    #expect(score.isSafe == false)
    #expect(score.rationale == "27: wrong")
  }

  @Test
  func `a field neither side states is not scored`() throws {
    let score = try Self.score("LDA", expected: Self.dtwGold, actual: Self.dtwGold)
    #expect(score.readsExpected == nil)
    #expect(score.isSafe == nil)
  }

  @Test
  func `the same number in another unit is unsafe`() throws {
    let metres = Self.extraction(
      Self.effect("09R", partialClosure: Self.closedPortion, TORA: .init(value: 6787, unit: .m)),
      Self.effect("27L", partialClosure: Self.closedPortion)
    )
    let score = try Self.score("TORA", expected: Self.dtwGold, actual: metres)
    #expect(score.readsExpected == false)
    #expect(score.isSafe == false)
  }

  @Test
  func `an invented value is unsafe and a dropped one is a safe miss`() throws {
    let gold = Self.extraction(Self.effect("09R", TORA: .init(value: 6787, unit: .ft)))
    let withLDA = Self.extraction(
      Self.effect("09R", TORA: .init(value: 6787, unit: .ft), LDA: .init(value: 1, unit: .ft))
    )
    let invented = try Self.score("LDA", expected: gold, actual: withLDA)
    #expect(invented.readsExpected == nil)
    #expect(invented.isSafe == false)

    let dropped = try Self.score("TORA", expected: gold, actual: Self.extraction())
    #expect(dropped.readsExpected == false)
    #expect(dropped.isSafe == true)
  }

  @Test
  func `contaminants repeated for several thirds read as the one the label lists`() throws {
    let ice = Extraction.Contaminant(type: .ice, coveragePercent: 10, depth: nil),
      snow = Extraction.Contaminant(type: .compactedSnow, coveragePercent: 20, depth: nil)
    let gold = Self.extraction(Self.effect("31", contaminants: [snow, ice]))
    let repeated = Self.extraction(Self.effect("31", contaminants: [ice, snow, ice, ice]))
    #expect(try Self.score("contaminants", expected: gold, actual: repeated).readsExpected == true)
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
