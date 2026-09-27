/// The ``ReadingFormat`` text the decoder lets the model write, as a ``BytePattern``.
///
/// It constrains form and ranges: designators `01`–`36` with an optional side, codes `0`–`6`, thirds
/// `1`–`3`, coverage `0`–`100`, the schema's units and contaminant types, and the counts the schema caps
/// (12 effects, 3 codes, 9 contaminants). Whether a fact is stated at all is the model's call.
@_spi(NOTAMModelRuntime)
public enum ReadingGrammar {
  private static let maximumEffects = 12, maximumCodes = 3, maximumContaminants = 9
  private static let maximumIntegerDigits = 6, maximumFractionDigits = 6
  private static let maximumReferenceLength = 80
  private static let compassPoints = [
    "N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSW", "SW", "WSW", "W", "WNW", "NW",
    "NNW"
  ]

  /// The whole output: a cancellation, nothing, or up to 12 effect lines.
  public static let pattern: BytePattern = .either([
    .literal(ReadingFormat.canceled),
    .literal(ReadingFormat.nothing),
    effect + .repeated(.literal("\n") + effect, minimum: 0, maximum: maximumEffects - 1)
  ])

  private static var effect: BytePattern {
    .sequence([
      .literal("RWY "), .either([runway, .literal(ReadingFormat.aerodrome)]),
      (.literal(" CLSD") + .literal(" PART").optional).optional,
      (.literal(" LEN ") + measure(["ft", "m"])).optional,
      (.literal(" END ") + closedEnd).optional,
      (.literal(" DTHR ") + measure(["ft", "m"])).optional,
      (.literal(" DD") + declaredDistances).optional,
      (.literal(" SFC") + (.literal(" CC ") + codes).optional + .literal(" ") + contaminants)
        .optional,
      (.literal(" OBST") + obstacle).optional
    ])
  }

  private static var direction: BytePattern {
    .either([
      .literal("0") + .range("1"..."9"),
      .range("1"..."2") + .range("0"..."9"),
      .literal("3") + .range("0"..."6")
    ]) + .oneOf(["L", "C", "R"]).optional
  }

  private static var runway: BytePattern { direction + (.literal("/") + direction).optional }

  private static var closedEnd: BytePattern {
    .either([.oneOf(compassPoints), direction, .oneOf(["thresholdEnd", "departureEnd"])])
  }

  private static var digit: BytePattern { .range("0"..."9") }

  /// A positive decimal without exponent or leading zeros.
  private static var number: BytePattern {
    let fraction = (.literal(".") + .repeated(digit, minimum: 1, maximum: maximumFractionDigits))
      .optional
    return .either([
      .range("1"..."9") + .repeated(digit, minimum: 0, maximum: maximumIntegerDigits - 1)
        + fraction,
      .literal("0.") + .repeated(digit, minimum: 1, maximum: maximumFractionDigits)
    ])
  }

  private static var codes: BytePattern {
    let code = BytePattern.range("0"..."6")
    return code + .repeated(.literal("/") + code, minimum: 0, maximum: maximumCodes - 1)
  }

  private static var contaminants: BytePattern {
    .either([
      contaminant
        + .repeated(.literal(",") + contaminant, minimum: 0, maximum: maximumContaminants - 1),
      .literal(ReadingFormat.absent)
    ])
  }

  private static var contaminant: BytePattern {
    let types = NOTAMExtraction.ContaminantType.allCases.map(\.rawValue)
    let percent = BytePattern.either([
      digit, .range("1"..."9") + digit, .literal("100")
    ])
    return .sequence([
      .oneOf(types),
      (.literal("@") + .range("1"..."3")).optional,
      (.literal("%") + percent).optional,
      (.literal("~") + measure(["in", "mm"])).optional
    ])
  }

  private static var obstacle: BytePattern {
    let referenceCharacter = BytePattern.byte(ByteSet((0x20...0x7E).filter { $0 != 0x22 }))
    return .sequence([
      (.literal(" AGL ") + measure(["ft", "m"])).optional,
      (.literal(" MSL ") + measure(["ft", "m"])).optional,
      (.literal(" DIST ") + measure(["ft", "m", "nm"])).optional,
      (.literal(" REF \"")
        + .repeated(referenceCharacter, minimum: 1, maximum: maximumReferenceLength)
        + .literal("\"")).optional,
      (.literal(" BRG ") + .either([number, .literal("0")])).optional,
      (.literal(" POS ") + position).optional
    ])
  }

  /// Decimal degrees, or degrees-minutes-seconds as written (`453036N 0732322W`).
  private static var position: BytePattern {
    let signed = BytePattern.literal("-").optional + number
    let seconds =
      BytePattern.repeated(digit, minimum: 2, maximum: 2)
      + (.literal(".") + .repeated(digit, minimum: 1, maximum: 3)).optional
    let latitude =
      BytePattern.repeated(digit, minimum: 4, maximum: 4) + seconds + .oneOf(["N", "S"])
    let longitude =
      BytePattern.repeated(digit, minimum: 5, maximum: 5) + seconds + .oneOf(["E", "W"])
    return .either([signed + .literal(" ") + signed, latitude + .literal(" ") + longitude])
  }

  /// At least one named distance, in the order TORA, TODA, ASDA, LDA.
  private static var declaredDistances: BytePattern {
    let names = ["TORA", "TODA", "ASDA", "LDA"]
    return .either(
      names.indices.map { first in
        .sequence([distance(names[first])] + names[(first + 1)...].map { distance($0).optional })
      }
    )
  }

  private static func measure(_ units: [String]) -> BytePattern { number + .oneOf(units) }

  private static func distance(_ name: String) -> BytePattern {
    .literal(" \(name) ") + measure(["ft", "m"])
  }
}
