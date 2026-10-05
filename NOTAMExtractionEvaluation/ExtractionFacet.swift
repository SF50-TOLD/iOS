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

/// One scored field of ``NOTAMExtraction``, compared place by place.
///
/// A runway effect's fields are aligned by its runway direction, and an obstacle's by the runway end
/// its reference names, so the order the model emits them in never matters. A value filed under the
/// wrong direction counts as missing from one and invented on another, because the app would apply
/// it to the wrong runway. Both readings are canonicalized first, so contaminants compare as
/// deduplicated sets.
struct ExtractionFacet: Sendable {
  let name: String
  private let values: @Sendable (NOTAMExtraction) -> [(place: String?, value: AnyFacetValue)]

  private init<Value: Equatable & Sendable>(
    effect name: String,
    _ value: @escaping @Sendable (NOTAMExtraction.RunwayEffect) -> Value?
  ) {
    self.name = name
    values = { extraction in
      extraction.effects.compactMap { effect in
        value(effect).map { (effect.runway, AnyFacetValue($0, matches: ==)) }
      }
    }
  }

  private init<Value: Equatable & Sendable>(
    obstacle name: String,
    _ value: @escaping @Sendable (NOTAMExtraction.Obstacle) -> Value?
  ) {
    self.name = name
    values = { extraction in
      extraction.obstacles.compactMap { obstacle in
        value(obstacle).map { (obstacle.reference?.runway, AnyFacetValue($0, matches: ==)) }
      }
    }
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

  private static func rationale(_ outcomes: [(place: String?, outcome: FacetOutcome)]) -> String {
    outcomes.filter { $0.outcome != .absent && $0.outcome != .correct }
      .map { "\($0.place ?? "aerodrome"): \($0.outcome)" }
      .joined(separator: "; ")
  }

  func score(expected: NOTAMExtraction, actual: NOTAMExtraction) -> FacetScore {
    let outcomes = outcomesByPlace(expected: expected.canonicalized, actual: actual.canonicalized)
    return FacetScore(
      readsExpected: Self.readsExpected(outcomes.map(\.outcome)),
      isSafe: Self.isSafe(outcomes.map(\.outcome)),
      rationale: Self.rationale(outcomes)
    )
  }

  private func outcomesByPlace(expected: NOTAMExtraction, actual: NOTAMExtraction)
    -> [(place: String?, outcome: FacetOutcome)]
  {
    let expectedByPlace = valuesByPlace(expected), actualByPlace = valuesByPlace(actual)
    let places = Set(expectedByPlace.keys).union(actualByPlace.keys)
      .sorted { ($0 ?? "") < ($1 ?? "") }
    return places.map { place in
      let outcome = Self.outcome(
        expected: expectedByPlace[place] ?? [],
        actual: actualByPlace[place] ?? []
      )
      return (place, outcome)
    }
  }

  private func valuesByPlace(_ extraction: NOTAMExtraction) -> [String?: [AnyFacetValue]] {
    Dictionary(grouping: values(extraction), by: \.place).mapValues { $0.map(\.value) }
  }
}

extension ExtractionFacet {
  /// Every scored field, in the schema's order.
  static let all: [ExtractionFacet] = [
    .init(effect: "closure") { $0.closure == NOTAMExtraction.Closure.none ? nil : $0.closure },
    .init(effect: "partialClosure") { $0.partialClosure },
    .init(effect: "closedLength") { $0.partialClosure?.length },
    .init(effect: "closedEnd") { $0.partialClosure?.end },
    .init(effect: "thresholdDisplacement") { $0.thresholdDisplacement },
    .init(effect: "TORA") { $0.declaredDistances?.TORA },
    .init(effect: "LDA") { $0.declaredDistances?.LDA },
    .init(effect: "rwyCC") { $0.surfaceCondition?.rwyCC },
    .init(effect: "contaminants") { $0.surfaceCondition?.contaminants },
    .init(obstacle: "obstacleHeight") { $0.height },
    .init(obstacle: "obstacleDistance") { obstacle in
      obstacle.distance.map { ObstacleDistance(distance: $0, reference: obstacle.reference) }
    },
    .init(obstacle: "obstacleDirection") { $0.direction }
  ]

  /// An obstacle's distance and what it's measured from, which mean nothing apart.
  private struct ObstacleDistance: Equatable, Sendable {
    let distance: NOTAMExtraction.Distance, reference: NOTAMExtraction.ObstacleReference?
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
