internal import RegexBuilder

/// Whether every number, closed end and compass direction in a model's reading is one the NOTAM
/// text states.
///
/// The model copies values; it never computes them. A length, depth, height, distance, coverage or
/// bearing that isn't written in the NOTAM — allowing thousands separators and fractions such as
/// `1/8` — was invented, so the reading is refused rather than proposed. So is a closed end or
/// direction the text doesn't name: `thresholdEnd` needs FIRST (or FST), `departureEnd` needs LAST,
/// and a compass point or runway end must be written.
@_spi(NOTAMModelRuntime)
public enum ReadingGrounding {
  private static let compassWords = [
    "N": "NORTH", "S": "SOUTH", "E": "EAST", "W": "WEST", "NE": "NORTHEAST", "NW": "NORTHWEST",
    "SE": "SOUTHEAST", "SW": "SOUTHWEST"
  ]

  private static var number: Regex<Substring> { #/\d[\d,]*(?:\.\d+)?/# }
  private static var fraction: Regex<(Substring, Substring?, Substring, Substring)> {
    #/(?:(\d+)\s+)?(\d+)\/(\d+)/#
  }

  /// Whether `extraction` states only numbers, ends and directions `text` does.
  public static func isGrounded(_ extraction: NOTAMExtraction, in text: String) -> Bool {
    let stated = statedNumbers(in: text)
    let words =
      extraction.effects.compactMap { $0.partialClosure?.end }
      + extraction.obstacles.compactMap { obstacle in
        if case .compass(let point) = obstacle.direction { point.rawValue } else { nil }
      }
    return values(of: extraction).allSatisfy(stated.contains)
      && words.allSatisfy { isStated($0, in: text) }
  }

  private static func isStated(_ word: String, in text: String) -> Bool {
    let words: [String]
    switch word {
      case "thresholdEnd": words = ["FIRST", "FST"]
      case "departureEnd": words = ["LAST"]
      default: words = [word] + [compassWords[word]].compactMap(\.self)
    }
    return words.contains { word in
      text.contains(
        Regex {
          Anchor.wordBoundary; word; Anchor.wordBoundary
        }
      )
    }
  }

  private static func values(of extraction: NOTAMExtraction) -> [Double] {
    let effectValues = extraction.effects.flatMap { effect in
      [
        effect.partialClosure?.length, effect.thresholdDisplacement,
        effect.declaredDistances?.TORA, effect.declaredDistances?.LDA
      ]
      .compactMap { $0?.value }
        + (effect.surfaceCondition?.contaminants ?? []).flatMap { contaminant in
          [contaminant.coveragePercent.map(Double.init), contaminant.depth?.value]
            .compactMap(\.self)
        }
    }
    let obstacleValues = extraction.obstacles.flatMap { obstacle in
      var values = [obstacle.height?.value, obstacle.distance?.value].compactMap(\.self)
      if case .degrees(let degrees) = obstacle.direction { values.append(degrees) }
      return values
    }
    return effectValues + obstacleValues
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
}
