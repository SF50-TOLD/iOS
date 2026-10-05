public import FoundationModels

/// Runway-performance facts stated in one NOTAM, as a model reads them, or as a formatted report
/// states them (``init(_:)``).
///
/// ``NOTAMExtraction`` mirrors `schema/notam_extraction.schema.json` (version ``schemaVersion``) in the
/// Model Training repository, whose `SCHEMA.md` is the authority on every field. It records only what the
/// NOTAM text states — every unstated fact is `nil` — and never a derived value: shortening, contamination
/// categories, the governing RwyCC and which obstacle lies ahead of a takeoff are the app's arithmetic,
/// not the model's.
@Generable(
  description:
    "Runway-performance facts stated in one NOTAM. Record only what the text states; anything not stated is null.",
  representNilExplicitlyInGeneratedContent: true
)
public struct NOTAMExtraction: Codable, Sendable, Equatable {
  /// The Model Training schema version this type mirrors.
  public static let schemaVersion = "2.0.0"

  /// Whether the NOTAM text itself says it is a cancellation.
  @Guide(
    description:
      "True only when the text says NOTAMC, CANCELED, CANCELLED or CNL. When true, effects and obstacles are empty."
  )
  public var isCanceled: Bool

  /// One entry per runway direction the NOTAM states a performance-relevant fact about.
  @Guide(
    description:
      "One entry per runway direction the text states a runway-performance fact about; a pair such as 09/27 gives one entry for 09 and one for 27. Empty when nothing affects runway performance.",
    // Bounds a runaway repetition; no NOTAM states facts about more directions.
    .maximumCount(12)
  )
  public var effects: [RunwayEffect]

  /// Obstacles in the aerodrome environment with a stated height or distance.
  @Guide(
    description:
      "Obstacles such as cranes or towers in the aerodrome environment, with a stated height or distance. Empty when none.",
    // Bounds a runaway repetition.
    .maximumCount(8)
  )
  public var obstacles: [Obstacle]

  /// Creates an extraction.
  public init(isCanceled: Bool, effects: [RunwayEffect], obstacles: [Obstacle] = []) {
    self.isCanceled = isCanceled
    self.effects = effects
    self.obstacles = obstacles
  }
}

extension NOTAMExtraction {
  /// The facts one NOTAM states about one runway direction.
  @Generable(representNilExplicitlyInGeneratedContent: true)
  public struct RunwayEffect: Codable, Sendable, Equatable {
    /// One runway direction, zero-padded; `nil` for the aerodrome or all runways.
    @Guide(
      description:
        "One runway direction as written, zero-padded (\"09R\"). Null for the aerodrome or all runways.",
      // The model's guided generation rejects character classes, so digits and suffixes are alternations.
      /(0|1|2|3)(0|1|2|3|4|5|6|7|8|9)(L|C|R)?/
    )
    public var runway: String?

    /// Which operations the text states this direction is closed to.
    @Guide(
      description:
        "none unless the text says this direction is closed. both for CLSD, CLOSED or NOT AVBL; landing or takeoff when closed for only that operation. A closure only at stated times, or only to aircraft that exclude a light jet, is none."
    )
    public var closure: Closure

    /// A stated closed portion of this direction.
    @Guide(
      description: "A stated closed portion of this direction. Null when no portion is closed."
    )
    public var partialClosure: PartialClosure?

    /// The stated total displacement of this direction's threshold.
    @Guide(
      description:
        "Stated threshold displacement (THR DSPLCD, DTHR) or relocation; for a further displacement, the stated total only."
    )
    public var thresholdDisplacement: Length?

    /// TORA and LDA as stated for this direction.
    @Guide(description: "TORA and LDA stated for this direction. Null when neither is stated.")
    public var declaredDistances: DeclaredDistances?

    /// A runway condition report (FICON, RSC or SNOWTAM).
    @Guide(description: "A runway condition report: FICON, RSC or SNOWTAM.")
    public var surfaceCondition: SurfaceCondition?

    /// Creates an effect.
    public init(
      runway: String?,
      closure: Closure,
      partialClosure: PartialClosure? = nil,
      thresholdDisplacement: Length? = nil,
      declaredDistances: DeclaredDistances? = nil,
      surfaceCondition: SurfaceCondition? = nil
    ) {
      self.runway = runway
      self.closure = closure
      self.partialClosure = partialClosure
      self.thresholdDisplacement = thresholdDisplacement
      self.declaredDistances = declaredDistances
      self.surfaceCondition = surfaceCondition
    }
  }

  /// Which operations a runway direction is closed to.
  @Generable
  public enum Closure: String, Codable, Sendable {
    /// The text states no closure.
    case none
    /// Closed for takeoff only.
    case takeoff
    /// Closed for landing only.
    case landing
    /// Closed for takeoff and landing.
    case both
  }

  /// A stated closed portion of a runway direction.
  @Generable(representNilExplicitlyInGeneratedContent: true)
  public struct PartialClosure: Codable, Sendable, Equatable {
    /// The closed portion's length, when stated.
    @Guide(description: "Length of the closed portion, when stated.")
    public var length: Length?

    /// Where the closed portion is, as stated: `thresholdEnd` (FIRST), `departureEnd` (LAST), a
    /// 16-point compass abbreviation, or a runway end.
    @Guide(
      description:
        "Where the closed portion is: thresholdEnd for FIRST, departureEnd for LAST, a compass abbreviation (\"W\"), or a runway end (\"27L\"). Null when not stated, or when FIRST or LAST is given against a pair.",
      // swiftlint:disable:next line_length
      /thresholdEnd|departureEnd|N|NNE|NE|ENE|E|ESE|SE|SSE|S|SSW|SW|WSW|W|WNW|NW|NNW|(0|1|2|3)(0|1|2|3|4|5|6|7|8|9)(L|C|R)?/
    )
    public var end: String?

    /// Creates a partial closure.
    public init(length: Length?, end: String?) {
      self.length = length
      self.end = end
    }
  }

  /// A length as stated, in the unit the NOTAM wrote it in.
  @Generable(representNilExplicitlyInGeneratedContent: true)
  public struct Length: Codable, Sendable, Equatable {
    /// The stated number.
    public var value: Double
    /// The unit written on the value or in its table header.
    public var unit: LengthUnit

    /// Creates a measurement.
    public init(value: Double, unit: LengthUnit) {
      self.value = value
      self.unit = unit
    }
  }

  /// Units a runway length or obstacle height is stated in.
  @Generable
  public enum LengthUnit: String, Codable, Sendable {
    /// Feet.
    case ft
    /// Metres.
    case m
  }

  /// A contaminant depth as stated.
  @Generable(representNilExplicitlyInGeneratedContent: true)
  public struct Depth: Codable, Sendable, Equatable {
    /// The stated number (fractions as decimals: 1/8IN → 0.125).
    public var value: Double
    /// The stated unit.
    public var unit: DepthUnit

    /// Creates a measurement.
    public init(value: Double, unit: DepthUnit) {
      self.value = value
      self.unit = unit
    }
  }

  /// Units a contaminant depth is stated in.
  @Generable
  public enum DepthUnit: String, Codable, Sendable {
    /// Inches.
    case `in`
    /// Millimetres.
    case mm
  }

  /// An obstacle distance as stated.
  @Generable(representNilExplicitlyInGeneratedContent: true)
  public struct Distance: Codable, Sendable, Equatable {
    /// The stated number.
    public var value: Double
    /// The stated unit.
    public var unit: DistanceUnit

    /// Creates a measurement.
    public init(value: Double, unit: DistanceUnit) {
      self.value = value
      self.unit = unit
    }
  }

  /// Units an obstacle distance is stated in.
  @Generable
  public enum DistanceUnit: String, Codable, Sendable {
    /// Feet.
    case ft
    /// Metres.
    case m
    /// Nautical miles.
    case nm
  }

  /// An obstacle height as stated, with its datum.
  @Generable(representNilExplicitlyInGeneratedContent: true)
  public struct Height: Codable, Sendable, Equatable {
    /// The stated number.
    public var value: Double
    /// The stated unit.
    public var unit: LengthUnit
    /// What the height is measured from.
    @Guide(
      description:
        "AGL for a height stated as AGL or labelled HEIGHT/HGT; MSL for one stated as MSL/AMSL or labelled ELEVATION/ELEV."
    )
    public var datum: HeightDatum

    /// Creates a height.
    public init(value: Double, unit: LengthUnit, datum: HeightDatum) {
      self.value = value
      self.unit = unit
      self.datum = datum
    }
  }

  /// What an obstacle height is measured from.
  @Generable
  public enum HeightDatum: String, Codable, Sendable {
    /// Above ground level.
    case AGL
    /// Above mean sea level.
    case MSL
  }

  /// Declared distances for one runway direction; each is `nil` unless stated with a unit.
  @Generable(representNilExplicitlyInGeneratedContent: true)
  public struct DeclaredDistances: Codable, Sendable, Equatable {
    // swiftlint:disable identifier_name
    /// Take-off run available.
    public var TORA: Length?
    /// Landing distance available.
    public var LDA: Length?
    // swiftlint:enable identifier_name

    /// Creates declared distances.
    public init(TORA: Length?, LDA: Length?) {
      self.TORA = TORA
      self.LDA = LDA
    }
  }

  /// A runway condition report.
  @Generable(representNilExplicitlyInGeneratedContent: true)
  public struct SurfaceCondition: Codable, Sendable, Equatable {
    /// Runway condition codes as reported, in reporting order.
    @Guide(
      description:
        "Codes as reported, in reporting order: \"5/5/3\" → [5, 5, 3]. Null when none reported.",
      .maximumCount(3),
      .element(.range(0...6))
    )
    public var rwyCC: [Int]?

    /// The distinct contaminants reported for the runway surface covered by the report.
    @Guide(
      description:
        "The distinct contaminants reported; one reported identically for several thirds is listed once. Exclude treatments, cleared width, REMAINDER and braking action.",
      // Three thirds of up to three contaminants each; bounds a runaway repetition.
      .maximumCount(9)
    )
    public var contaminants: [Contaminant]

    /// Creates a runway condition report.
    public init(rwyCC: [Int]?, contaminants: [Contaminant]) {
      self.rwyCC = rwyCC
      self.contaminants = contaminants
    }
  }

  /// One reported contaminant.
  @Generable(representNilExplicitlyInGeneratedContent: true)
  public struct Contaminant: Codable, Sendable, Equatable {
    /// The FAA AC 150/5200-30D contaminant.
    public var type: ContaminantType

    /// The stated coverage percentage.
    @Guide(
      description: "Stated percentage (40 PCT → 40). PATCHY and THIN are null.",
      .range(0...100)
    )
    public var coveragePercent: Int?

    /// The stated depth of the (top layer of the) contaminant.
    @Guide(description: "Stated depth of the top layer (1/8IN → 0.125 in).")
    public var depth: Depth?

    /// Creates a contaminant.
    public init(type: ContaminantType, coveragePercent: Int?, depth: Depth?) {
      self.type = type
      self.coveragePercent = coveragePercent
      self.depth = depth
    }
  }

  // The schema's own values are camelCase, so each case name is its wire value.
  // swiftlint:disable raw_value_for_camel_cased_codable_enum
  /// FAA AC 150/5200-30D contaminants as written in FICON NOTAMs.
  @Generable
  public enum ContaminantType: String, Codable, Sendable, CaseIterable {
    /// `WET`
    case wet
    /// `WATER`, `STANDING WATER`
    case water
    /// `SLUSH`
    case slush
    /// `WET SN`
    case wetSnow
    /// `DRY SN`
    case drySnow
    /// `COMPACTED SN`
    case compactedSnow
    /// `FROST`
    case frost
    /// `ICE`
    case ice
    /// `WET ICE`
    case wetIce
    /// `SLUSH OVER ICE`
    case slushOverIce
    /// `WATER OVER COMPACTED SN`
    case waterOverCompactedSnow
    /// `DRY SN OVER COMPACTED SN`
    case drySnowOverCompactedSnow
    /// `WET SN OVER COMPACTED SN`
    case wetSnowOverCompactedSnow
    /// `DRY SN OVER ICE`
    case drySnowOverIce
    /// `WET SN OVER ICE`
    case wetSnowOverIce
    /// Anything else (damp, mud, compacted snow gravel mix).
    case other
  }
  // swiftlint:enable raw_value_for_camel_cased_codable_enum

  /// An obstacle as reported.
  @Generable(representNilExplicitlyInGeneratedContent: true)
  public struct Obstacle: Codable, Sendable, Equatable {
    /// The stated height, with its datum.
    @Guide(
      description:
        "The stated height. When both MSL and AGL are stated, the MSL one; in \"<n>FT (<n>FT AGL)\" the first is MSL."
    )
    public var height: Height?

    /// The stated distance from ``reference``.
    public var distance: Distance?

    /// What ``distance`` is measured from; `nil` exactly when it is.
    @Guide(description: "What the distance is measured from. Null exactly when distance is null.")
    public var reference: ObstacleReference?

    /// The direction from ``reference``, as stated.
    @Guide(
      description:
        "Direction from the reference as stated: a 16-point compass word (\"WNW\") or degrees (\"RDL 114\"). Null for RIGHT OF CENTERLINE and the like."
    )
    public var direction: ObstacleDirection?

    /// Creates an obstacle.
    public init(
      height: Height?,
      distance: Distance?,
      reference: ObstacleReference?,
      direction: ObstacleDirection?
    ) {
      self.height = height
      self.distance = distance
      self.reference = reference
      self.direction = direction
    }
  }

  /// What an obstacle's distance is measured from.
  @Generable(representNilExplicitlyInGeneratedContent: true)
  public struct ObstacleReference: Codable, Sendable, Equatable {
    /// The kind of reference.
    @Guide(
      description:
        "departureEnd for DER, DEP END, BEYOND TORA; threshold for THR, APCH END; ARP for ARP or the airport identifier; other for anything else."
    )
    public var kind: ReferenceKind

    /// The runway end's direction for a departure end or threshold; `nil` for ARP and other.
    @Guide(
      description:
        "The runway end's direction for departureEnd and threshold; null for ARP and other.",
      /(0|1|2|3)(0|1|2|3|4|5|6|7|8|9)(L|C|R)?/
    )
    public var runway: String?

    /// Creates a reference.
    public init(kind: ReferenceKind, runway: String?) {
      self.kind = kind
      self.runway = runway
    }
  }

  // The schema's own values are camelCase, so each case name is its wire value.
  // swiftlint:disable raw_value_for_camel_cased_codable_enum
  /// The kind of point an obstacle's distance is measured from.
  @Generable
  public enum ReferenceKind: String, Codable, Sendable {
    /// A runway's departure end.
    case departureEnd
    /// A runway's threshold.
    case threshold
    /// The aerodrome reference point.
    case ARP
    /// Anything else: a taxiway, a town, a runway without a stated end.
    case other
  }
  // swiftlint:enable raw_value_for_camel_cased_codable_enum

  /// A 16-point compass direction.
  @Generable
  public enum CompassPoint: String, Codable, Sendable, CaseIterable {
    // swiftlint:disable identifier_name
    case N, NNE, NE, ENE, E, ESE, SE, SSE, S, SSW, SW, WSW, W, WNW, NW, NNW
    // swiftlint:enable identifier_name
  }

  /// An obstacle's direction from its reference: a compass word, or a bearing in degrees.
  ///
  /// It codes as the schema writes it: a string for a compass word, a number for degrees.
  @Generable
  public enum ObstacleDirection: Codable, Sendable, Equatable {
    /// A 16-point compass word.
    case compass(CompassPoint)
    /// A bearing in degrees, from 0 up to 360.
    case degrees(Double)

    /// Decodes a compass word or a number of degrees.
    public init(from decoder: any Decoder) throws {
      let container = try decoder.singleValueContainer()
      if let degrees = try? container.decode(Double.self) {
        self = .degrees(degrees)
      } else {
        self = .compass(try container.decode(CompassPoint.self))
      }
    }

    /// Encodes a compass word as a string and degrees as a number.
    public func encode(to encoder: any Encoder) throws {
      var container = encoder.singleValueContainer()
      switch self {
        case .compass(let point): try container.encode(point)
        case .degrees(let degrees): try container.encode(degrees)
      }
    }
  }
}
