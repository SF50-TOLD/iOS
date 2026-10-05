import NOTAMModel
import Testing

@testable import SF50_Shared

struct `Auto-Fill outcomes` {
  private typealias Effect = NOTAMExtraction.RunwayEffect

  private static func feet(_ value: Double) -> NOTAMExtraction.Length {
    .init(value: value, unit: .ft)
  }

  private static func tora(_ value: Double, on runway: String = "09R") -> Effect {
    Effect(
      runway: runway,
      closure: .none,
      declaredDistances: .init(TORA: feet(value), LDA: nil)
    )
  }

  private static func closed(_ length: NOTAMExtraction.Length, on runway: String = "09R") -> Effect
  {
    Effect(runway: runway, closure: .none, partialClosure: .init(length: length, end: nil))
  }

  private static func rwyCC(_ code: Int, on runway: String? = "09R") -> Effect {
    Effect(
      runway: runway,
      closure: .none,
      surfaceCondition: .init(rwyCC: [code, code, code], contaminants: [])
    )
  }

  private static func outcome(reading: [Effect], label: [Effect], canceled: Bool = false)
    -> AutoFillOutcome
  {
    AutoFillOutcome.of(
      NOTAMExtractor.Reading(
        extraction: .init(isCanceled: false, effects: reading),
        source: .parser
      ),
      expected: .init(isCanceled: canceled, effects: label)
    )
  }

  @Test
  func `scores a TORA that flatters the label as hazardous`() {
    #expect(Self.outcome(reading: [Self.tora(6500)], label: [Self.tora(6000)]) == .hazardous)
  }

  @Test
  func `scores a TORA below the label as cautious`() {
    #expect(Self.outcome(reading: [Self.tora(5500)], label: [Self.tora(6000)]) == .cautious)
  }

  @Test
  func `scores a closed length that flatters the label as hazardous`() {
    let outcome = Self.outcome(
      reading: [Self.closed(Self.feet(1000))],
      label: [Self.closed(Self.feet(1500))]
    )
    #expect(outcome == .hazardous)
  }

  @Test
  func `scores an offer that leaves out a value the label states as hazardous`() {
    var label = Self.closed(Self.feet(1500))
    label.surfaceCondition = .init(rwyCC: [3, 3, 3], contaminants: [])
    #expect(Self.outcome(reading: [Self.rwyCC(3)], label: [label]) == .hazardous)
  }

  @Test
  func `scores a shortening on a runway the label closes as hazardous`() {
    let outcome = Self.outcome(
      reading: [Self.closed(Self.feet(1000))],
      label: [Effect(runway: "09R", closure: .both)]
    )
    #expect(outcome == .hazardous)
  }

  @Test
  func `scores a takeoff offer on a runway closed only for landing on its own merits`() {
    var label = Self.tora(6000)
    label.closure = .landing
    #expect(Self.outcome(reading: [Self.tora(6000)], label: [label]) == .exact)
  }

  @Test
  func `scores a less severe runway condition code as hazardous`() {
    #expect(Self.outcome(reading: [Self.rwyCC(5)], label: [Self.rwyCC(2)]) == .hazardous)
  }

  @Test
  func `scores no offer where the label has one as manual`() {
    #expect(Self.outcome(reading: [], label: [Self.closed(Self.feet(1500))]) == .manual)
  }

  @Test
  func `scores a value filed under the wrong runway as cautious`() {
    let outcome = Self.outcome(
      reading: [Self.closed(Self.feet(1500), on: "27L")],
      label: [Self.closed(Self.feet(1500))]
    )
    #expect(outcome == .cautious)
  }

  @Test
  func `scores the same length in feet and metres as exact`() {
    let outcome = Self.outcome(
      reading: [Self.closed(.init(value: 457, unit: .m))],
      label: [Self.closed(Self.feet(1500))]
    )
    #expect(outcome == .exact)
  }

  @Test
  func `scores a pair's directions read in either order as exact`() {
    let outcome = Self.outcome(
      reading: [Self.closed(Self.feet(1500), on: "27L"), Self.closed(Self.feet(1500))],
      label: [Self.closed(Self.feet(1500)), Self.closed(Self.feet(1500), on: "27L")]
    )
    #expect(outcome == .exact)
  }

  @Test
  func `scores values read from a cancelled NOTAM as cautious`() {
    let outcome = Self.outcome(
      reading: [Self.closed(Self.feet(1500))],
      label: [],
      canceled: true
    )
    #expect(outcome == .cautious)
  }

  @Test
  func `scores an aerodrome-wide label as silent`() {
    let outcome = Self.outcome(reading: [Self.rwyCC(3, on: nil)], label: [Self.rwyCC(3, on: nil)])
    #expect(outcome == .silent)
  }

  @Test
  func `scores a declared LDA that hides a stated displacement as hazardous`() {
    let displaced = Effect(
      runway: "09R",
      closure: .none,
      thresholdDisplacement: .init(value: 300, unit: .m)
    )
    var withLDA = displaced
    withLDA.declaredDistances = .init(TORA: nil, LDA: .init(value: 1900, unit: .m))
    #expect(Self.outcome(reading: [withLDA], label: [displaced]) == .hazardous)
  }

  @Test
  func `scores a closure read as a displaced threshold as hazardous`() {
    let displaced = Effect(
      runway: "09R",
      closure: .none,
      thresholdDisplacement: .init(value: 300, unit: .m)
    )
    #expect(
      Self.outcome(reading: [displaced], label: [Self.closed(.init(value: 300, unit: .m))])
        == .hazardous
    )
  }
}
