/// FAA obstacle NOTAMs: `[<id>] OBST <type> (ASN <number>) <position> (<n>NM <compass> <reference>)
/// <n>FT (<n>FT AGL) [FLAGGED] [AND] [LGTD]`.
///
/// The format defines its first height as MSL and both heights in feet. A compass direction isn't a
/// numeric bearing, so the bearing is never recorded. The obstacle's runway is the one its reference
/// names (`APCH END RWY 03L`), if any.
enum FAAObstacleReport {
  private static var report:
    Regex<(Substring, Substring, Substring, Substring, Substring, Substring?, Substring?)>
  {
    #/(?:[A-Z0-9]{3,4} )?OBST [A-Z ]+? \(ASN [^)]*\) (\d{6}(?:\.\d+)?[NS])(\d{7}(?:\.\d+)?[EW]) \((\d*\.?\d+)NM (?:N|NNE|NE|ENE|E|ESE|SE|SSE|S|SSW|SW|WSW|W|WNW|NW|NNW) ([A-Z0-9 ]+)\) (?:(\d+)FT|UNKNOWN) \((?:(\d+)FT|UNKNOWN) AGL\)(?: FLAGGED)?(?: AND)?(?: LGTD)?\.?/#
  }
  private static var runwayInReference: Regex<(Substring, Substring)> { /\bRWY (\d{1,2}[LCR]?)$/ }

  static func parse(_ report: ReportText) -> NOTAMExtraction? {
    guard let match = try? Self.report.wholeMatch(in: report.text),
      let latitude = DMSCoordinate.latitude(match.1),
      let longitude = DMSCoordinate.longitude(match.2),
      let distanceNM = Double(match.3), distanceNM > 0
    else { return nil }
    let reference = String(match.4)
    let runway = reference.firstMatch(of: runwayInReference).flatMap {
      RunwayDesignator.normalize($0.1)
    }
    let obstacle = NOTAMExtraction.Obstacle(
      heightAGL: feet(match.6),
      heightMSL: feet(match.5),
      distance: .init(value: distanceNM, unit: .nm),
      distanceReference: reference,
      bearingDegrees: nil,
      latitude: latitude,
      longitude: longitude
    )
    let effect = NOTAMExtraction.RunwayEffect(
      runway: runway,
      closure: .none,
      closedLength: nil,
      closedEnd: nil,
      thresholdDisplacement: nil,
      declaredDistances: nil,
      surfaceCondition: nil,
      obstacle: obstacle
    )
    return .init(isCanceled: false, effects: [effect])
  }

  private static func feet(_ written: Substring?) -> NOTAMExtraction.Length? {
    guard let written, let value = Double(written), value > 0 else { return nil }
    return .init(value: value, unit: .ft)
  }
}
