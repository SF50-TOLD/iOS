import NOTAMModel

@testable import SF50_Shared

/// How one field of one NOTAM's extraction compares with its gold label.
enum FacetOutcome: Comparable {
  /// Neither the label nor the extraction states the field.
  case absent
  /// The extraction states exactly what the label does.
  case correct
  /// The label states the field and the extraction doesn't: a blank the pilot fills in.
  case missed
  /// Both state the field, with different values: a wrong number or category.
  case wrong
  /// The extraction states a field the label doesn't: a value the NOTAM never gave.
  case invented

  /// Whether the pilot would be shown a value the NOTAM doesn't support.
  var isUnsafe: Bool { self == .wrong || self == .invented }

  /// Whether the label states the field on this runway.
  var isStatedByLabel: Bool { self == .correct || self == .missed || self == .wrong }
}

/// How one field of one NOTAM's extraction scores against its label.
struct FacetScore: Equatable {
  /// Whether the extraction reads every value the label states; `nil` when the label states none.
  let readsExpected: Bool?
  /// Whether every value the extraction states is one the label supports; `nil` when neither the
  /// label nor the extraction states the field, so a NOTAM silent on it is not a trial.
  let isSafe: Bool?
  /// The runways where the extraction departs from the label, and how.
  let rationale: String
}

/// One scored field of ``NOTAMExtraction``, compared runway by runway.
///
/// Effects are aligned by runway designator, so the order the model emits them in never matters. A
/// value filed under the wrong designator counts as missing from one runway and invented on another,
/// because the app would apply it to the wrong runway.
struct ExtractionFacet: Sendable {
  private static let coordinateTolerance = 1e-4

  let name: String
  let isDistance: Bool
  private let values: @Sendable (NOTAMExtraction.RunwayEffect) -> [AnyFacetValue]

  private init<Value: Equatable & Sendable>(
    _ name: String,
    isDistance: Bool = false,
    _ value: @escaping @Sendable (NOTAMExtraction.RunwayEffect) -> Value?,
    matches: @escaping @Sendable (Value, Value) -> Bool = { $0 == $1 }
  ) {
    self.name = name
    self.isDistance = isDistance
    values = { effect in value(effect).map { [AnyFacetValue($0, matches: matches)] } ?? [] }
  }

  private static func outcome(expected: [AnyFacetValue], actual: [AnyFacetValue]) -> FacetOutcome {
    switch (expected.isEmpty, actual.isEmpty) {
      case (true, true): .absent
      case (true, false): .invented
      case (false, true): .missed
      case (false, false): AnyFacetValue.sameMultiset(expected, actual) ? .correct : .wrong
    }
  }

  private static func readsExpected(_ outcomes: [FacetOutcome]) -> Bool? {
    let stated = outcomes.filter(\.isStatedByLabel)
    return stated.isEmpty ? nil : stated.allSatisfy { $0 == .correct }
  }

  private static func isSafe(_ outcomes: [FacetOutcome]) -> Bool? {
    let trials = outcomes.filter { $0 != .absent }
    return trials.isEmpty ? nil : !trials.contains(where: \.isUnsafe)
  }

  private static func rationale(_ outcomes: [(runway: String?, outcome: FacetOutcome)]) -> String {
    outcomes.filter { $0.outcome != .absent && $0.outcome != .correct }
      .map { "\($0.runway ?? "aerodrome"): \($0.outcome)" }
      .joined(separator: "; ")
  }

  func score(expected: NOTAMExtraction, actual: NOTAMExtraction) -> FacetScore {
    let outcomes = outcomesByRunway(expected: expected, actual: actual)
    return FacetScore(
      readsExpected: Self.readsExpected(outcomes.map(\.outcome)),
      isSafe: Self.isSafe(outcomes.map(\.outcome)),
      rationale: Self.rationale(outcomes)
    )
  }

  private func outcomesByRunway(expected: NOTAMExtraction, actual: NOTAMExtraction)
    -> [(runway: String?, outcome: FacetOutcome)]
  {
    let expectedByRunway = valuesByRunway(expected), actualByRunway = valuesByRunway(actual)
    let runways = Set(expectedByRunway.keys).union(actualByRunway.keys)
      .sorted { ($0 ?? "") < ($1 ?? "") }
    return runways.map { runway in
      let outcome = Self.outcome(
        expected: expectedByRunway[runway] ?? [],
        actual: actualByRunway[runway] ?? []
      )
      return (runway, outcome)
    }
  }

  private func valuesByRunway(_ extraction: NOTAMExtraction) -> [String?: [AnyFacetValue]] {
    extraction.effects.reduce(into: [:]) { byRunway, effect in
      let found = values(effect)
      if !found.isEmpty { byRunway[effect.runway, default: []] += found }
    }
  }
}

extension ExtractionFacet {
  /// Every scored field, in the order the decision table lists them.
  static let all: [ExtractionFacet] = [
    .init("closure") { $0.closure == NOTAMExtraction.Closure.none ? nil : $0.closure },
    .init("closedLength", isDistance: true) { $0.closedLength },
    .init("closedEnd") { $0.closedEnd },
    .init("thresholdDisplacement", isDistance: true) { $0.thresholdDisplacement },
    .init("TORA", isDistance: true) { $0.declaredDistances?.TORA },
    .init("TODA", isDistance: true) { $0.declaredDistances?.TODA },
    .init("ASDA", isDistance: true) { $0.declaredDistances?.ASDA },
    .init("LDA", isDistance: true) { $0.declaredDistances?.LDA },
    .init("rwyCC") { $0.surfaceCondition?.rwyCC },
    .init("contaminants") { $0.surfaceCondition.map { canonical($0.contaminants) } },
    .init("obstacleHeightAGL") { $0.obstacle?.heightAGL },
    .init("obstacleHeightMSL") { $0.obstacle?.heightMSL },
    .init("obstaclePosition", { effect in position(effect.obstacle) }, matches: samePosition)
  ]

  private static func canonical(_ contaminants: [NOTAMExtraction.Contaminant]) -> [NOTAMExtraction
    .Contaminant]
  {
    contaminants.sorted {
      ($0.runwayThird ?? 0, $0.type.rawValue) < ($1.runwayThird ?? 0, $1.type.rawValue)
    }
  }

  private static func position(_ obstacle: NOTAMExtraction.Obstacle?) -> Position? {
    guard let obstacle, obstacle.latitude != nil || obstacle.longitude != nil else { return nil }
    return Position(latitude: obstacle.latitude, longitude: obstacle.longitude)
  }

  /// Positions match only as whole pairs: half a position is never the one the NOTAM gave.
  private static func samePosition(_ lhs: Position, _ rhs: Position) -> Bool {
    guard let lhsLatitude = lhs.latitude, let lhsLongitude = lhs.longitude,
      let rhsLatitude = rhs.latitude, let rhsLongitude = rhs.longitude
    else { return false }
    return abs(lhsLatitude - rhsLatitude) <= coordinateTolerance
      && abs(lhsLongitude - rhsLongitude) <= coordinateTolerance
  }

  private struct Position: Equatable, Sendable {
    let latitude: Double?, longitude: Double?
  }
}

/// A facet value with its own notion of a match, so facets of different types share one comparison.
private struct AnyFacetValue: Sendable {
  private let value: any Sendable
  private let matchesValue: @Sendable (any Sendable) -> Bool

  init<Value: Equatable & Sendable>(
    _ value: Value,
    matches: @escaping @Sendable (Value, Value) -> Bool
  ) {
    self.value = value
    matchesValue = { other in (other as? Value).map { matches(value, $0) } ?? false }
  }

  static func sameMultiset(_ lhs: [Self], _ rhs: [Self]) -> Bool {
    guard lhs.count == rhs.count else { return false }
    var unmatched = rhs
    for element in lhs {
      guard let index = unmatched.firstIndex(where: { element.matchesValue($0.value) }) else {
        return false
      }
      unmatched.remove(at: index)
    }
    return true
  }
}
