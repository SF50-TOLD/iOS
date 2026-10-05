public import Foundation

extension PreviewHelper {
  /// Generates sample NOTAMResponse objects for preview purposes
  /// - Parameters:
  ///   - count: Number of NOTAMs to generate
  ///   - icaoLocation: ICAO code for the airport (default: "KOAK")
  ///   - baseTime: Reference time for generating effective dates (default: now)
  /// - Returns: Array of NOTAMResponse objects with varied statuses and lengths, classified by
  ///   ``NOTAMRelevance``
  public func generateNOTAMs(
    count: Int,
    icaoLocation: String = "KOAK",
    baseTime: Date = .now
  ) -> [NOTAMResponse] {
    let loremTexts = [
      "RWY CLSD",
      "THR DISPLACED 320M. EFFECTIVE OPR LENGTH 1420M",
      "THR RWY 30 DISPLACED 320M. RWY 12/30 EFFECTIVE OPR LENGTH 1420M.\nDISPLACED THR LIGHT OPR",
      "RWY 12/30 CLSD DUE WIP. AVBL FOR HOSP FLIGHTS WITH 60 MIN PN",
      "PAPI U/S",
      "LIGHTING SYSTEM UPGRADE IN PROGRESS. EXPECT REDUCED VISIBILITY OF THR LIGHTS",
      "OBST CRANE 1200FT AMSL 0.3NM E OF THR RWY 30",
      "NAVAID VOR OUT OF SERVICE. USE GPS APPROACH ONLY",
      "TWY A CLSD BTN TWY B AND TWY C. USE ALT ROUTING VIA TWY D",
      "BIRD ACTIVITY REPORTED IN VICINITY OF AIRPORT. EXERCISE CAUTION",
      "FUEL AVBL H24",
      "PPR FOR ACF WINGSPAN GREATER THAN 80FT. CONTACT AIRPORT OPS 48HR IN ADVANCE",
      "RWY SURFACE TREATMENT IN PROGRESS 0800-1600 LOCAL. EXPECT DELAYS",
      "APRON REPAINTING. TAXI WITH CAUTION. FOLLOW MARSHALLER INSTRUCTIONS",
      "ILS RWY 30 GLIDESLOPE U/S. LOC ONLY APPROACH AVAILABLE"
    ]

    let purposes = ["N", "B", "M", "O"]
    let scopes = ["A", "E", "W", nil]
    let trafficTypes = ["I", "IV", "K", nil]

    return (0..<count).map { index in
      let letter = String(UnicodeScalar(65 + index % 26)!)
      let notamId = "\(letter)\(unsafe String(format: "%04d", 8000 + index))/2025"

      // Vary the effective times for different statuses
      let hourOffset: TimeInterval =
        switch index % 5 {
          case 0:  // Active - started 1 hour ago, ends in 2 hours
            -3600
          case 1:  // Warning - starts in 2 hours
            7200
          case 2:  // Expired - started 1 day ago, ended 2 hours ago
            -86400
          case 3:  // Future - starts in 1 day
            86400
          default:  // Active - started 30 min ago, ends in 4 hours
            -1800
        }

      let effectiveStart = baseTime.addingTimeInterval(hourOffset)

      // Vary end times
      let effectiveEnd: Date? =
        switch index % 5 {
          case 2:  // Expired
            baseTime.addingTimeInterval(-7200)
          case 3, 4:  // Some have end times
            effectiveStart.addingTimeInterval(14400)
          default:  // Some are permanent
            index.isMultiple(of: 3) ? nil : effectiveStart.addingTimeInterval(10800)
        }

      // Vary NOTAM text lengths
      let textIndex = index % loremTexts.count
      let notamText = loremTexts[textIndex]

      // Some NOTAMs have schedules
      let schedule = index.isMultiple(of: 7) ? "0800-1800" : nil

      return NOTAMResponse(
        id: index + 1,
        notamId: notamId,
        icaoLocation: icaoLocation,
        effectiveStart: effectiveStart,
        effectiveEnd: effectiveEnd,
        schedule: schedule,
        notamText: notamText,
        qLine: nil,
        purpose: purposes[index % purposes.count],
        scope: scopes[index % scopes.count],
        trafficType: trafficTypes[index % trafficTypes.count]
      )
      .classifiedForRelevance
    }
  }
}

extension NOTAMResponse {
  /// NOTAMs for Oakland runway 30 that the formatted-report parsers read without the on-device model:
  /// a FICON report, which proposes a landing runway condition code, and an FAA obstacle report off
  /// the departure end, which proposes a takeoff obstacle's height and distance. For previews and UI
  /// tests.
  ///
  /// - Parameter baseTime: The time both NOTAMs are in effect around.
  public static func readableSamples(baseTime: Date = .now) -> [Self] {
    let texts = [
      "OAK RWY 30 FICON 3/3/3 100 PCT 1/8IN WATER OBS AT 2609260325.",
      "OAK OBST CRANE (ASN 2026-AWP-1234-OE) 374300N1221230W (0.4NM NW DEP END RWY 30) 185FT (170FT AGL) FLAGGED AND LGTD."
    ]
    return texts.enumerated().map { index, text in
      Self(
        id: 9000 + index,
        notamId: "A\(9000 + index)/26",
        icaoLocation: "KOAK",
        effectiveStart: baseTime.addingTimeInterval(-3600),
        effectiveEnd: baseTime.addingTimeInterval(86400),
        schedule: nil,
        notamText: text,
        qLine: nil,
        purpose: "N",
        scope: "A",
        trafficType: "IV"
      )
      .classifiedForRelevance
    }
  }
}
