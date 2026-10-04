internal import Foundation
internal import RegexBuilder

/// FAA obstacle NOTAMs: `[<id>] OBST <type> (ASN <number>) <position> (<n>NM <compass> <reference>)
/// <n>FT (<n>FT AGL) [FLAGGED] [AND] [LGTD]`.
///
/// The format defines its first height as MSL and both heights in feet. The obstacle's runway is
/// the one whose end its reference names (`APCH END RWY 03L`), if any.
final class FAAObstacleReport: ReportFormat {
  private static let latitudeDegreeDigits = 2, longitudeDegreeDigits = 3, minuteSecondDigits = 4

  private let distanceNM = Reference<Double>()
  private let distanceReference = Reference<Substring>()
  private let direction = Reference<FormattedReport.CompassPoint>()
  private let heightMSL = Reference<Double?>()
  private let heightAGL = Reference<Double?>()
  private let referencedRunway = Reference<Substring>()
  private let referencedEnd = Reference<FormattedReport.RunwayEnd.End>()

  private lazy var obstacleReport = Regex {
    Optionally {
      Repeat(3...4) { ReportGrammar.alphanumeric }
      " "
    }
    "OBST "
    OneOrMore(CharacterClass("A"..."Z", .anyOf(" ")), .reluctant)
    " (ASN "
    ZeroOrMore(CharacterClass.anyOf(")").inverted)
    ") "
    Self.coordinate(degreeDigits: Self.latitudeDegreeDigits, hemispheres: "NS")
    Self.coordinate(degreeDigits: Self.longitudeDegreeDigits, hemispheres: "EW")
    " ("
    TryCapture(as: distanceNM) {
      ZeroOrMore(ReportGrammar.digit)
      Optionally(".")
      OneOrMore(ReportGrammar.digit)
    } transform: {
      Double($0).flatMap { $0 > 0 ? $0 : nil }
    }
    "NM "
    TryCapture(as: direction) {
      ReportGrammar.alternation(of: FormattedReport.CompassPoint.allCases.map(\.rawValue))
    } transform: {
      FormattedReport.CompassPoint(rawValue: String($0))
    }
    " "
    Capture(as: distanceReference) { OneOrMore(CharacterClass("A"..."Z", "0"..."9", .anyOf(" "))) }
    ") "
    Self.height(as: heightMSL)
    " ("
    Self.height(as: heightAGL)
    " AGL)"
    Optionally(" FLAGGED")
    Optionally(" AND")
    Optionally(" LGTD")
    Optionally(".")
  }

  /// A reference that is a runway end and nothing else (`APCH END RWY 03L`, `DEP END RWY 30`).
  private lazy var runwayEnd = Regex {
    Capture(as: referencedEnd) {
      ChoiceOf {
        "APCH"
        "DEP"
      }
    } transform: {
      $0 == "APCH" ? .approach : .departure
    }
    " END RWY "
    Capture(as: referencedRunway) {
      Repeat(ReportGrammar.digit, 1...2)
      Optionally(CharacterClass.anyOf("LCR"))
    }
  }

  /// A latitude or longitude in degrees, minutes and seconds (`403906N`, `0734931.5W`).
  private static func coordinate(degreeDigits: Int, hemispheres: String) -> Regex<Substring> {
    Regex {
      Repeat(ReportGrammar.digit, count: degreeDigits + minuteSecondDigits)
      Optionally {
        "."
        OneOrMore(ReportGrammar.digit)
      }
      CharacterClass.anyOf(hemispheres)
    }
  }

  /// A height in feet, or `UNKNOWN`.
  private static func height(as reference: Reference<Double?>) -> some RegexComponent {
    ChoiceOf {
      Regex {
        Capture(as: reference) {
          OneOrMore(ReportGrammar.digit)
        } transform: {
          Double($0)
        }
        "FT"
      }
      "UNKNOWN"
    }
  }

  func parse(_ report: ReportText) -> FormattedReport? {
    guard let match = report.text.wholeMatch(of: obstacleReport) else { return nil }
    let reference = match[distanceReference], runwayEnd = runwayEnd(named: reference)
    let obstacle = FormattedReport.Obstacle(
      heightAGL: feet(match[heightAGL]),
      heightMSL: feet(match[heightMSL]),
      distance: .init(value: match[distanceNM], unit: .nauticalMiles),
      distanceReference: String(reference),
      direction: match[direction],
      runwayEnd: runwayEnd
    )
    return .init(effects: [.init(runway: runwayEnd?.runway, obstacle: obstacle)])
  }

  private func runwayEnd(named reference: Substring) -> FormattedReport.RunwayEnd? {
    guard let match = reference.wholeMatch(of: runwayEnd),
      let runway = RunwayDesignator.normalize(match[referencedRunway])
    else { return nil }
    return .init(runway: runway, end: match[referencedEnd])
  }

  private func feet(_ value: Double?) -> Measurement<UnitLength>? {
    value.flatMap { $0 > 0 ? .init(value: $0, unit: .feet) : nil }
  }
}
