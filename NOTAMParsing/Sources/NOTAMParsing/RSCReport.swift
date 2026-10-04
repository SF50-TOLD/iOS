internal import RegexBuilder

/// Canadian RSC runway surface condition reports: an optional aerodrome line, one `RSC <rwy> [n/n/n]
/// <list>. <remarks>.` report per runway, then optional non-GRF information and remarks.
///
/// The list follows the FICON grammar. Only remarks known to state nothing a report records — the
/// validity period, RWYCC downgrades, chemical residue, cleared widths, windrows, work in progress —
/// may follow it. The non-GRF section (CRFI, taxiway and apron remarks) isn't recorded.
final class RSCReport: ReportFormat {
  private static let maximumPreambleLength = 80

  private let runway = Reference<Substring>()
  private let codes = Reference<[Int]?>()
  private let text = Reference<Substring>()

  private let scanner: ReportScanner, contaminantList: ContaminantList

  private lazy var reportStart = Regex {
    Anchor.wordBoundary
    "RSC "
    Lookahead {
      ReportGrammar.word
      " "
    }
  }

  private lazy var addendumStart = Regex {
    Anchor.wordBoundary
    ChoiceOf {
      "ADDN NON-GRF/TALPA INFO:"
      "RMK:"
    }
  }

  /// `<rwy> [n/n/n] <list>. <remarks>.`
  private lazy var runwayReport = Regex {
    Capture(as: runway) { ReportGrammar.word }
    " "
    Optionally {
      Capture(as: codes) {
        RunwayConditionCodes.pattern
      } transform: {
        RunwayConditionCodes.values(of: $0)
      }
      " "
    }
    Capture(as: text) { OneOrMore(.any) }
  }

  private lazy var ignorableClause = Regex {
    ChoiceOf {
      Regex {
        "VALID "
        OneOrMore(.any)
      }
      Regex {
        ChoiceOf {
          "TOUCHDOWN"
          "MIDPOINT"
          "ROLLOUT"
          "ALL"
        }
        " RWYCC DOWNGRADED"
      }
      "CHEMICAL RESIDUE PRESENT"
      "RESIDUAL CHEMICAL PRESENT"
      "FORMATE RESIDUE"
      "LOOSE SAND APPLIED"
      Regex {
        "UREA TREATED"
        Optionally {
          " "
          OneOrMore(.any)
        }
      }
      "TURN AND TAXI WITH CAUTION"
      Regex {
        "CHEMICAL"
        Optionally("LY")
        " "
        ChoiceOf {
          "APPLIED"
          "REAPPLIED"
          "TREATED"
        }
      }
      Regex {
        "SLIPPERY CONDITIONS"
        Optionally {
          ChoiceOf {
            " ON TAXIWAYS"
            " HIGH SPEED EXITS"
          }
        }
      }
      "PATCHY CONTAMINANT"
      Regex {
        ChoiceOf {
          "CLEARING/SWEEPING"
          "CLEARING"
          "SWEEPING"
          "SANDING"
          "PLOWING"
          "SNOW REMOVAL"
        }
        " IN PROGRESS"
      }
      Regex {
        Optionally("RUNWAY SURFACE ")
        ChoiceOf {
          "GRADED"
          "SANDED"
          "SCARIFIED"
        }
      }
      Regex {
        OneOrMore(ReportGrammar.digit)
        ChoiceOf {
          "FT"
          "M"
        }
        " WIDTH"
      }
      Regex {
        Optionally {
          OneOrMore(ReportGrammar.digit)
          ChoiceOf {
            "FT"
            "IN"
          }
          " "
        }
        "WINDROWS"
        Optionally {
          " "
          OneOrMore(.any)
        }
      }
      Regex {
        "REMAINING WIDTH "
        OneOrMore(.any)
      }
      "SNOW DRIFTS ON RUNWAY"
      "RUNWAY SNOW GRAVEL MIX"
    }
  }

  init(scanner: ReportScanner, contaminantList: ContaminantList) {
    self.scanner = scanner
    self.contaminantList = contaminantList
  }

  func parse(_ report: ReportText) -> FormattedReport? {
    let text = report.text[...]
    let addendum = text.firstMatch(of: addendumStart)
    let main = addendum.map { text[..<$0.range.lowerBound] } ?? text
    if let addendum, scanner.statesPerformanceFact(text[addendum.range.lowerBound...]) {
      return nil
    }

    let starts = main.matches(of: reportStart).map(\.range)
    guard let first = starts.first, isIgnorablePreamble(main[..<first.lowerBound]) else {
      return nil
    }
    var effects: [FormattedReport.RunwayEffect] = []
    for (index, start) in starts.enumerated() {
      let end = index + 1 < starts.count ? starts[index + 1].lowerBound : main.endIndex
      guard let effect = effect(main[start.upperBound..<end]) else { return nil }
      effects.append(effect)
    }
    return FormattedReport.mergingRepeatedReports(effects)
  }

  private func isIgnorablePreamble(_ preamble: Substring) -> Bool {
    preamble.count <= Self.maximumPreambleLength && !preamble.contains("RWY")
      && !scanner.statesPerformanceFact(preamble)
  }

  private func effect(_ report: Substring) -> FormattedReport.RunwayEffect? {
    guard let match = report.wholeMatch(of: runwayReport),
      let runway = RunwayDesignator.normalize(match[runway])
    else { return nil }
    let sentences = match[text].trimmingSuffix(while: { $0 == " " || $0 == "." })
      .split(separator: ". ")
    guard let list = sentences.first, let contaminants = contaminantList.parse(list),
      sentences.dropFirst().allSatisfy(isIgnorableRemark)
    else { return nil }
    return .surfaceCondition(runway: runway, rwyCC: match[codes], contaminants: contaminants)
  }

  private func isIgnorableRemark(_ sentence: Substring) -> Bool {
    sentence.split(separator: ", ").allSatisfy { clause in
      !scanner.statesPerformanceFact(clause) && clause.wholeMatch(of: ignorableClause) != nil
    }
  }
}
