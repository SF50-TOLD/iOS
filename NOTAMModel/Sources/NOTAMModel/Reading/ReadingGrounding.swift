internal import RegexBuilder

/// Whether every number and closed end in a model's reading is one the NOTAM text states.
///
/// The model copies values; it never computes them. A length, depth, height, distance, coverage or
/// bearing that isn't written in the NOTAM — allowing thousands separators and fractions such as
/// `1/8` — or a position that isn't one of the NOTAM's degrees-minutes-seconds positions, was
/// invented, so the reading is refused rather than proposed. So is a closed end the text doesn't
/// name: `thresholdEnd` needs FIRST (or FST), `departureEnd` needs LAST, and a compass point or
/// runway end must be written.
@_spi(NOTAMModelRuntime)
public enum ReadingGrounding {
  private static let positionTolerance = 1e-6
  private static let compassWords = [
    "N": "NORTH", "S": "SOUTH", "E": "EAST", "W": "WEST", "NE": "NORTHEAST", "NW": "NORTHWEST",
    "SE": "SOUTHEAST", "SW": "SOUTHWEST"
  ]

  private static var number: Regex<Substring> { /\d[\d,]*(?:\.\d+)?/ }
  private static var fraction: Regex<(Substring, Substring?, Substring, Substring)> {
    /(?:(\d+)\s+)?(\d+)\/(\d+)/
  }
  private static var dmsPair: Regex<(Substring, Substring, Substring)> {
    /(\d{6}(?:\.\d{1,3})?\s?[NS])\s*[\/,]?\s*(\d{7}(?:\.\d{1,3})?\s?[EW])/
  }

  /// Whether `extraction` states only numbers `text` does.
  public static func isGrounded(_ extraction: NOTAMExtraction, in text: String) -> Bool {
    let stated = statedNumbers(in: text), positions = statedPositions(in: text)
    return extraction.effects.allSatisfy { effect in
      values(of: effect).allSatisfy(stated.contains)
        && effect.closedEnd.map { isStated(closedEnd: $0, in: text) } ?? true
        && position(of: effect).map { position in
          positions.contains {
            abs($0.latitude - position.latitude) < positionTolerance
              && abs($0.longitude - position.longitude) < positionTolerance
          }
        } ?? true
    }
  }

  private static func isStated(closedEnd: String, in text: String) -> Bool {
    let words: [String]
    switch closedEnd {
      case "thresholdEnd": words = ["FIRST", "FST"]
      case "departureEnd": words = ["LAST"]
      default: words = [closedEnd] + [compassWords[closedEnd]].compactMap(\.self)
    }
    return words.contains { word in
      text.contains(
        Regex {
          Anchor.wordBoundary; word; Anchor.wordBoundary
        }
      )
    }
  }

  private static func values(of effect: NOTAMExtraction.RunwayEffect) -> [Double] {
    let distances = effect.declaredDistances.map { [$0.TORA, $0.TODA, $0.ASDA, $0.LDA] } ?? []
    var values = ([effect.closedLength, effect.thresholdDisplacement] + distances).compactMap {
      $0?.value
    }
    for contaminant in effect.surfaceCondition?.contaminants ?? [] {
      values += [contaminant.coveragePercent.map(Double.init), contaminant.depth?.value].compactMap(
        \.self
      )
    }
    if let obstacle = effect.obstacle {
      values += [obstacle.heightAGL?.value, obstacle.heightMSL?.value, obstacle.distance?.value]
        .compactMap(\.self)
      values += [obstacle.bearingDegrees].compactMap(\.self)
    }
    return values
  }

  private static func position(of effect: NOTAMExtraction.RunwayEffect) -> (
    latitude: Double, longitude: Double
  )? {
    guard let latitude = effect.obstacle?.latitude, let longitude = effect.obstacle?.longitude
    else {
      return nil
    }
    return (latitude, longitude)
  }

  private static func statedNumbers(in text: String) -> Set<Double> {
    var numbers = Set(
      text.matches(of: number).compactMap { Double($0.output.replacing(",", with: "")) }
    )
    for match in text.matches(of: fraction) {
      guard let numerator = Double(match.2), let denominator = Double(match.3), denominator > 0
      else {
        continue
      }
      numbers.insert((match.1.flatMap { Double($0) } ?? 0) + numerator / denominator)
    }
    return numbers
  }

  private static func statedPositions(in text: String) -> [(latitude: Double, longitude: Double)] {
    text.matches(of: dmsPair).compactMap { match in
      let latitude = match.1.filter { $0 != " " }, longitude = match.2.filter { $0 != " " }
      guard let north = DMSCoordinate.latitude(latitude),
        let east = DMSCoordinate.longitude(longitude)
      else { return nil }
      return (north, east)
    }
  }
}
