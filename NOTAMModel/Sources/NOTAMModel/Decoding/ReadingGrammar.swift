/// The ``ReadingFormat`` text the decoder lets the model write, as a ``BytePattern``.
///
/// It constrains form and ranges: designators `01`–`36` with an optional side, codes `0`–`6`,
/// coverage `0`–`100`, degrees below 360, the schema's units, contaminant types and references, and
/// the counts the schema caps (12 effects, then 8 obstacles, 3 codes, 9 contaminants). Whether a
/// fact is stated at all is the model's call.
@_spi(NOTAMModelRuntime)
public enum ReadingGrammar {
  private static let maximumEffects = 12, maximumObstacles = 8, maximumCodes = 3,
    maximumContaminants = 9
  private static let maximumIntegerDigits = 6, maximumFractionDigits = 6

  /// The whole output: a cancellation, nothing, or effect lines followed by obstacle lines.
  public static let pattern: BytePattern = .either([
    .literal(ReadingFormat.canceled),
    .literal(ReadingFormat.nothing),
    effect + .repeated(.literal("\n") + effect, minimum: 0, maximum: maximumEffects - 1)
      + .repeated(.literal("\n") + obstacle, minimum: 0, maximum: maximumObstacles),
    obstacle + .repeated(.literal("\n") + obstacle, minimum: 0, maximum: maximumObstacles - 1)
  ])

  private static var effect: BytePattern {
    .sequence([
      .literal("RWY "), .either([runway, .literal(ReadingFormat.aerodrome)]),
      (.literal(" CLSD") + .oneOf([" TKOF", " LDG"]).optional).optional,
      (.literal(" PART") + (.literal(" ") + measure(["ft", "m"])).optional
        + (.literal(" END ") + closedEnd).optional).optional,
      (.literal(" DTHR ") + measure(["ft", "m"])).optional,
      (.literal(" TORA ") + measure(["ft", "m"])).optional,
      (.literal(" LDA ") + measure(["ft", "m"])).optional,
      (.literal(" SFC") + (.literal(" CC ") + codes).optional + .literal(" ") + contaminants)
        .optional
    ])
  }

  private static var obstacle: BytePattern {
    .sequence([
      .literal("OBST"),
      (.oneOf([" AGL ", " MSL "]) + measure(["ft", "m"])).optional,
      (.literal(" DIST ") + measure(["ft", "m", "nm"]) + .literal(" ") + reference).optional,
      (.literal(" DIR ") + .either([compassPoint, degrees])).optional
    ])
  }

  private static var runway: BytePattern {
    .either([
      .literal("0") + .range("1"..."9"),
      .range("1"..."2") + .range("0"..."9"),
      .literal("3") + .range("0"..."6")
    ]) + .oneOf(["L", "C", "R"]).optional
  }

  private static var compassPoint: BytePattern {
    .oneOf(NOTAMExtraction.CompassPoint.allCases.map(\.rawValue))
  }

  private static var closedEnd: BytePattern {
    .either([compassPoint, runway, .oneOf(["thresholdEnd", "departureEnd"])])
  }

  private static var reference: BytePattern {
    .either([.oneOf(["DER ", "THR "]) + runway, .oneOf(["ARP", "OTHER"])])
  }

  private static var digit: BytePattern { .range("0"..."9") }

  private static var fraction: BytePattern {
    .literal(".") + .repeated(digit, minimum: 1, maximum: maximumFractionDigits)
  }

  /// A positive decimal without exponent or leading zeros.
  private static var number: BytePattern {
    .either([
      .range("1"..."9") + .repeated(digit, minimum: 0, maximum: maximumIntegerDigits - 1)
        + fraction.optional,
      .literal("0") + fraction
    ])
  }

  /// A bearing from 0 up to, but not including, 360.
  private static var degrees: BytePattern {
    let whole = BytePattern.either([
      digit,
      .range("1"..."9") + digit,
      .range("1"..."2") + digit + digit,
      .literal("3") + .range("0"..."5") + digit
    ])
    return whole + fraction.optional
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
    let percent = BytePattern.either([digit, .range("1"..."9") + digit, .literal("100")])
    return .sequence([
      .oneOf(types),
      (.literal("%") + percent).optional,
      (.literal("~") + measure(["in", "mm"])).optional
    ])
  }

  private static func measure(_ units: [String]) -> BytePattern { number + .oneOf(units) }
}
