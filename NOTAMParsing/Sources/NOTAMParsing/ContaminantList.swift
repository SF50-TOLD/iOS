internal import Foundation
internal import RegexBuilder

/// The contaminant list of an FAA FICON or Canadian RSC report: one list for the whole runway, or
/// three comma-separated lists, one per third in reporting order.
///
/// Each list is a series of contaminants joined by `AND`, each written
/// `[<n> PCT | PATCHY | THIN] [<depth>] <contaminant>`, among treatments, cleared widths, braking
/// action and snowbanks, which aren't recorded. `REMAINDER` ends a list: what lies outside the
/// cleared width isn't recorded either. `DRY` is a list with no contaminant. Any word the grammar
/// doesn't know makes the whole list unreadable.
final class ContaminantList {
  typealias Contaminant = FormattedReport.Contaminant

  private static let thirdsPerRunway = 3
  private static let maximumPercent = 100

  private static let unrecordedPhrases = [
    "DEICED LIQUID", "DEICED SOLID", "DEICED", "SANDED", "SWEPT", "PLOWED", "TREATED",
    "CHEMICALLY TREATED", "WID", "WIDE", "SNOWBANKS", "BERMS", "WINDROWS"
  ]
  private static let brakingActions = ["NIL", "POOR", "MEDIUM", "GOOD"]
  private static let banks = ["SNOWBANKS", "BERMS", "WINDROWS"]

  private let coverage = Reference<Int?>()
  private let depthWhole = Reference<Double?>()
  private let depthNumerator = Reference<Double?>()
  private let depthDenominator = Reference<Double?>()
  private let depthDecimal = Reference<Double?>()
  private let depthUnit = Reference<Substring?>()
  private let phrase = Reference<Substring>()

  private let vocabulary: ContaminantVocabulary

  /// `[<n> PCT | PATCHY | THIN] [<depth>] <contaminant>`.
  private lazy var contaminantPattern = Regex {
    Optionally {
      ChoiceOf {
        Regex {
          Capture(as: coverage) {
            Repeat(ReportGrammar.digit, 1...3)
          } transform: {
            Int($0)
          }
          " PCT"
        }
        "PATCHY"
        "THIN"
      }
      " "
    }
    Optionally {
      depthPattern
      " "
    }
    Capture(as: phrase) { vocabulary.phrase }
  }

  /// `<n>/<n>IN`, `<n> <n>/<n>IN`, or `<n>[.<n>]IN`, in inches or millimetres.
  private lazy var depthPattern = Regex {
    ChoiceOf {
      Regex {
        Optionally {
          Capture(as: depthWhole) {
            OneOrMore(ReportGrammar.digit)
          } transform: {
            Double($0)
          }
          " "
        }
        Capture(as: depthNumerator) {
          OneOrMore(ReportGrammar.digit)
        } transform: {
          Double($0)
        }
        "/"
        Capture(as: depthDenominator) {
          OneOrMore(ReportGrammar.digit)
        } transform: {
          Double($0)
        }
      }
      Regex {
        Capture(as: depthDecimal) {
          OneOrMore(ReportGrammar.digit)
          Optionally {
            "."
            OneOrMore(ReportGrammar.digit)
          }
        } transform: {
          Double($0)
        }
      }
    }
    Capture(as: depthUnit) {
      depthUnitPattern
    } transform: {
      $0
    }
    ReportGrammar.tokenEnd
  }

  private lazy var depthUnitPattern = Regex {
    ChoiceOf {
      "IN"
      "MM"
    }
  }

  /// Text a list carries but that isn't recorded.
  private lazy var unrecorded = Regex {
    ChoiceOf {
      "AND"
      ReportGrammar.alternation(of: Self.unrecordedPhrases)
      Regex {
        OneOrMore(ReportGrammar.digit)
        ChoiceOf {
          "FT"
          "M"
        }
      }
      Regex {
        "BA "
        brakingAction
        Optionally {
          " TO "
          brakingAction
        }
      }
      Regex {
        depthPattern
        " "
        ReportGrammar.alternation(of: Self.banks)
      }
    }
    ReportGrammar.tokenEnd
  }

  private lazy var brakingAction = ReportGrammar.alternation(of: Self.brakingActions)

  private lazy var remainder = Regex {
    "REMAINDER"
    ReportGrammar.tokenEnd
  }

  private lazy var dry = Regex {
    "DRY"
    ReportGrammar.tokenEnd
  }

  init(vocabulary: ContaminantVocabulary) {
    self.vocabulary = vocabulary
  }

  /// Reads a whole list, or returns `nil` if any of it is unreadable.
  func parse(_ text: Substring) -> [Contaminant]? {
    let thirds = text.split(separator: ",", omittingEmptySubsequences: false)
    switch thirds.count {
      case 1:
        return parseThird(thirds[0], number: nil)
      case Self.thirdsPerRunway:
        var contaminants: [Contaminant] = []
        for (offset, third) in thirds.enumerated() {
          guard let parsed = parseThird(third, number: offset + 1) else { return nil }
          contaminants += parsed
        }
        return contaminants
      default:
        return nil
    }
  }

  private func parseThird(_ text: Substring, number: Int?) -> [Contaminant]? {
    var rest = text.droppingLeadingSpaces, contaminants: [Contaminant] = [], isDry = false
    while !rest.isEmpty, rest.prefixMatch(of: remainder) == nil {
      if let match = rest.prefixMatch(of: unrecorded) {
        rest = rest[match.range.upperBound...]
      } else if let match = rest.prefixMatch(of: contaminantPattern) {
        guard let contaminant = contaminant(from: match, third: number) else { return nil }
        contaminants.append(contaminant)
        rest = rest[match.range.upperBound...]
      } else if let match = rest.prefixMatch(of: dry) {
        isDry = true
        rest = rest[match.range.upperBound...]
      } else {
        return nil
      }
      rest = rest.droppingLeadingSpaces
    }
    switch (isDry, contaminants.isEmpty) {
      case (true, true): return []
      case (false, false): return contaminants
      default: return nil
    }
  }

  /// The contaminant `match` states; `nil` when its coverage is over 100% or its depth isn't more
  /// than zero.
  private func contaminant<Output>(from match: Regex<Output>.Match, third: Int?) -> Contaminant? {
    let coveragePercent = match[coverage], depth = depth(from: match)
    guard let type = ContaminantVocabulary.type(of: match[phrase]),
      (coveragePercent ?? 0) <= Self.maximumPercent,
      depth.map({ $0.value > 0 && $0.value.isFinite }) ?? true
    else { return nil }
    return .init(type: type, runwayThird: third, coveragePercent: coveragePercent, depth: depth)
  }

  private func depth<Output>(from match: Regex<Output>.Match) -> Measurement<UnitLength>? {
    guard let unit = match[depthUnit] else { return nil }
    let value =
      match[depthDecimal]
      ?? (match[depthWhole] ?? 0) + (match[depthNumerator] ?? 0) / (match[depthDenominator] ?? 1)
    return .init(value: value, unit: unit == "MM" ? .millimeters : .inches)
  }
}
