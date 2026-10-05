import Foundation
import NOTAMModel
import NOTAMParsing

@testable import SF50_Shared

/// How what Auto-Fill would offer from one NOTAM compares with what its gold label implies.
///
/// The offer is what ``NOTAMProposalMapper`` proposes for each review screen — one runway direction
/// and one operation — and the value Auto-Fill would write is the first one proposed. It is compared
/// with the most conservative value the label implies, on each runway of a ``RunwayBracket``, since
/// a shortening worked out from a declared distance or a displaced threshold depends on the runway.
/// Cases run from best to worst, and a NOTAM's outcome is its worst screen's on its worst runway.
///
/// Obstacles aren't scored: only a formatted report proposes one, never a model reading.
enum AutoFillOutcome: Comparable {
  /// Neither the label nor the reading offers anything.
  case silent
  /// The offer equals the label's.
  case exact
  /// The label has values the reading doesn't offer, so the pilot enters them by hand.
  case manual
  /// Every difference from the label makes performance look worse.
  case cautious
  /// A value makes performance look better than the label's, the offer leaves out a value the
  /// label has, or it shortens a runway the label closes.
  case hazardous

  /// The label, as a reading whose every field may be proposed.
  static func label(_ expected: NOTAMExtraction) -> NOTAMExtractor.Reading {
    NOTAMExtractor.Reading(extraction: expected, source: .parser)
  }

  /// The outcome of the offers `reading` makes, against the label `expected`.
  static func of(_ reading: NOTAMExtractor.Reading, expected: NOTAMExtraction) -> Self {
    let label = label(expected)
    return Screen.all(in: [reading.extraction, expected])
      .map { $0.outcome(offering: reading, against: label) }
      .max() ?? .silent
  }

  /// Whether `reading` offers anything on any screen it names.
  static func offersAnything(_ reading: NOTAMExtractor.Reading) -> Bool {
    Screen.all(in: [reading.extraction]).contains { $0.offersAnything(reading) }
  }
}

extension AutoFillOutcome {
  /// One runway direction and operation: what the NOTAM editor shows at once.
  struct Screen {
    private static let notamID = "evaluated", exactToleranceMeters = 1.0

    let direction: String, operation: SF50_Shared.Operation
    /// The runways the screen is scored on.
    let runways: [ProposalRunway]

    /// Every screen the extractions' effects name.
    static func all(in extractions: [NOTAMExtraction]) -> [Self] {
      let designators = extractions.flatMap(\.effects).compactMap(\.runway),
        directions = Set(designators.flatMap(NOTAMParsing.RunwayDesignator.directions(of:)))
      return directions.sorted().flatMap { direction in
        let runways = RunwayBracket(direction: direction, extractions: extractions).runways
        return SF50_Shared.Operation.allCases.map {
          Self(direction: direction, operation: $0, runways: runways)
        }
      }
    }

    /// A length lower than the label's flatters performance: less runway lost, a lower obstacle.
    private static func compare(
      offered: Measurement<UnitLength>?,
      expected: Measurement<UnitLength>?
    ) -> AutoFillOutcome {
      switch (offered, expected) {
        case (nil, nil): .exact
        case (nil, .some): .hazardous
        case (.some, nil): .cautious
        case let (offered?, expected?):
          if abs((offered - expected).converted(to: .meters).value) <= exactToleranceMeters {
            .exact
          } else {
            offered < expected ? .hazardous : .cautious
          }
      }
    }

    private static func compare(offered: Contamination?, expected: Contamination?)
      -> AutoFillOutcome
    {
      switch (offered, expected) {
        case (nil, nil): .exact
        case (nil, .some): .hazardous
        case (.some, nil): .cautious
        case let (offered?, expected?):
          if offered == expected {
            .exact
          } else {
            offered.flatters(expected) ? .hazardous : .cautious
          }
      }
    }

    /// Whether `reading` offers anything on this screen, on any of its runways.
    func offersAnything(_ reading: NOTAMExtractor.Reading) -> Bool {
      runways.contains { !offer(from: reading, on: $0, choosing: .filled).isEmpty }
    }

    /// How this screen's offer from `reading` compares with the one from `label`, on the runway
    /// where it compares worst.
    func outcome(offering reading: NOTAMExtractor.Reading, against label: NOTAMExtractor.Reading)
      -> AutoFillOutcome
    {
      runways.map { outcome(offering: reading, against: label, on: $0) }.max() ?? .silent
    }

    private func outcome(
      offering reading: NOTAMExtractor.Reading,
      against label: NOTAMExtractor.Reading,
      on runway: ProposalRunway
    ) -> AutoFillOutcome {
      let offered = offer(from: reading, on: runway, choosing: .filled),
        expected = offer(from: label, on: runway, choosing: .mostConservative)
      if offered.shortening != nil, isClosed(by: proposal(from: label, on: runway)) {
        return .hazardous
      }
      if offered.isEmpty { return expected.isEmpty ? .silent : .manual }
      return [
        Self.compare(offered: offered.shortening, expected: expected.shortening),
        Self.compare(offered: offered.contamination, expected: expected.contamination)
      ].max() ?? .exact
    }

    /// Whether `proposal` closes this screen's operation.
    private func isClosed(by proposal: NOTAMProposal) -> Bool {
      switch operation {
        case .takeoff: !proposal.closedForTakeoffBy.isEmpty
        case .landing: !proposal.closedForLandingBy.isEmpty
      }
    }

    private func offer(
      from reading: NOTAMExtractor.Reading,
      on runway: ProposalRunway,
      choosing selection: Selection
    ) -> Offer {
      let proposal = proposal(from: reading, on: runway).fields(for: operation)
      switch operation {
        case .takeoff:
          return Offer(
            shortening: selection.length(of: proposal.takeoffShortening),
            contamination: nil
          )
        case .landing:
          return Offer(
            shortening: selection.length(of: proposal.landingShortening),
            contamination: selection.contamination(of: proposal.contamination)
          )
      }
    }

    private func proposal(from reading: NOTAMExtractor.Reading, on runway: ProposalRunway)
      -> NOTAMProposal
    {
      NOTAMProposalMapper.proposal(from: reading, notamID: Self.notamID, for: runway)
    }
  }

  /// Synthetic runways that bracket any runway a NOTAM could be about.
  ///
  /// A shortening worked out from a declared distance depends on the published length, and one
  /// from a displaced threshold on the published displacement; one from a closed length depends on
  /// neither. Where the label and the reading work a shortening out from different stated values,
  /// which one flatters depends on the runway, and each difference grows steadily with the length
  /// or the displacement, so the worst case lies at an extreme: the shortest runway the stated
  /// lengths allow or a very long one, with no published displacement or one nearly as long as the
  /// stated displacements.
  struct RunwayBracket {
    private static let longest = Measurement(value: 100_000, unit: UnitLength.meters),
      margin = Measurement(value: 10, unit: UnitLength.meters),
      none = Measurement(value: 0, unit: UnitLength.meters)

    /// The runways at the bracket's corners.
    let runways: [ProposalRunway]

    init(direction: String, extractions: [NOTAMExtraction]) {
      let effects = Self.effects(on: direction, in: extractions)
      runways = Self.lengths(allowedBy: effects).flatMap { length in
        Self.publishedDisplacements(allowedBy: effects).map { displacement in
          ProposalRunway(
            name: direction,
            reciprocalName: nil,
            trueHeadingDegrees: 0,
            departureEndElevation: Self.none,
            publishedTakeoffRun: length,
            publishedLandingDistance: length,
            publishedDisplacement: displacement
          )
        }
      }
    }

    private static func effects(on direction: String, in extractions: [NOTAMExtraction])
      -> [NOTAMExtraction.RunwayEffect]
    {
      extractions.flatMap(\.effects).filter { effect in
        effect.runway.map { NOTAMParsing.RunwayDesignator.names(direction, in: $0) } ?? false
      }
    }

    /// The shortest runway every stated length fits on, and a very long one.
    private static func lengths(allowedBy effects: [NOTAMExtraction.RunwayEffect])
      -> [Measurement<UnitLength>]
    {
      let stated = effects.flatMap(statedLengths)
      return [(stated.max() ?? none) + margin, longest]
    }

    private static func statedLengths(_ effect: NOTAMExtraction.RunwayEffect)
      -> [Measurement<UnitLength>]
    {
      [
        effect.declaredDistances?.TORA, effect.declaredDistances?.LDA,
        effect.partialClosure?.length,
        effect.thresholdDisplacement
      ]
      .compactMap { $0?.measurement }
    }

    /// No published displacement, and one just short of the shortest stated displacement.
    private static func publishedDisplacements(allowedBy effects: [NOTAMExtraction.RunwayEffect])
      -> [Measurement<UnitLength>]
    {
      let stated = effects.compactMap { $0.thresholdDisplacement?.measurement }
      guard let smallest = stated.min(), smallest - margin > margin else { return [none] }
      return [none, smallest - margin]
    }
  }

  /// Which of a field's proposed values is compared.
  enum Selection {
    /// The value Auto-Fill writes: the first proposed.
    case filled
    /// The value that makes performance look worst: the longest shortening, the most severe
    /// condition.
    case mostConservative

    func length(of candidates: [Candidate<Measurement<UnitLength>>]) -> Measurement<UnitLength>? {
      switch self {
        case .filled: candidates.first?.value
        case .mostConservative: candidates.map(\.value).max()
      }
    }

    func contamination(of candidates: [Candidate<Contamination>]) -> Contamination? {
      switch self {
        case .filled: candidates.first?.value
        case .mostConservative:
          candidates.map(\.value).reduce(nil) { worst, next in
            guard let worst else { return next }
            return worst.flatters(next) && !next.flatters(worst) ? next : worst
          }
      }
    }
  }

  /// The values Auto-Fill would write into one screen.
  struct Offer {
    let shortening: Measurement<UnitLength>?, contamination: Contamination?

    var isEmpty: Bool { shortening == nil && contamination == nil }
  }
}

extension Contamination {
  /// Whether this condition makes performance look better than `other`. A runway condition code
  /// and a contaminant category have no order, so either flatters the other.
  fileprivate func flatters(_ other: Self) -> Bool {
    switch (self, other) {
      case let (.rwyCC(code), .rwyCC(otherCode)): code > otherCode
      case (.rwyCC, _), (_, .rwyCC): true
      default: severity < other.severity
    }
  }
}

extension NOTAMExtraction.Length {
  fileprivate var measurement: Measurement<UnitLength> {
    .init(value: value, unit: unit == .ft ? .feet : .meters)
  }
}
