public import FoundationModels

/// Runway-performance facts stated in one NOTAM, as the on-device model reads them.
///
/// ``NOTAMExtraction`` mirrors `schema/notam_extraction.schema.json` (version ``schemaVersion``) in the
/// Model Training repository, whose `SCHEMA.md` is the authority on every field. It records only what the
/// NOTAM text states — every unstated fact is `nil` — and never a derived value: shortening, per-direction
/// effects of a runway pair, contamination categories and the governing RwyCC are the app's arithmetic,
/// not the model's.
@Generable(
  description:
    "Runway-performance facts stated in one NOTAM. Record only what the text states; anything not stated is null.",
  representNilExplicitlyInGeneratedContent: true
)
public struct NOTAMExtraction: Codable, Sendable, Equatable {
  /// The Model Training schema version this type mirrors.
  public static let schemaVersion = "1.4.0"

  /// Whether the NOTAM text itself says it is a cancellation.
  @Guide(
    description:
      "True only when the text says NOTAMC, CANCELED, CANCELLED or CNL. When true, effects is empty."
  )
  public var isCanceled: Bool

  /// One entry per runway designator the NOTAM states a performance-relevant fact about.
  @Guide(
    description:
      "One entry per runway designator the text states a runway-performance fact about. Empty when nothing affects runway performance.",
    // Bounds a runaway repetition; no NOTAM states facts about more designators.
    .maximumCount(12)
  )
  public var effects: [RunwayEffect]

  /// Creates an extraction.
  public init(isCanceled: Bool, effects: [RunwayEffect]) {
    self.isCanceled = isCanceled
    self.effects = effects
  }
}

extension NOTAMExtraction {
  /// The facts one NOTAM states about one runway designator.
  @Generable(representNilExplicitlyInGeneratedContent: true)
  public struct RunwayEffect: Codable, Sendable, Equatable {
    /// The designator as written, zero-padded; a pair is written with a slash. `nil` for the aerodrome.
    @Guide(
      description:
        "Runway designator as written, zero-padded (\"09R\"); a pair with a slash (\"09R/27L\"). Null for the aerodrome or all runways.",
      // The model's guided generation rejects character classes, so digits and suffixes are alternations.
      /(0|1|2|3)(0|1|2|3|4|5|6|7|8|9)(L|C|R)?(\/(0|1|2|3)(0|1|2|3|4|5|6|7|8|9)(L|C|R)?)?/
    )
    public var runway: String?

    /// The closure this effect states.
    @Guide(
      description:
        "full: runway closed. partial: a stated portion is closed. none: no closure stated."
    )
    public var closure: Closure

    /// Length of a partial closure, when stated.
    @Guide(description: "Length of the closed portion; only for a partial closure.")
    public var closedLength: Length?

    /// Which end a partial closure is at, as stated: a compass point, a runway end, or `thresholdEnd` /
    /// `departureEnd` for FIRST / LAST, relative to ``runway``.
    @Guide(
      description:
        "Where a partial closure is, as stated: a compass abbreviation (\"W\"), a runway end (\"27L\"), or thresholdEnd for FIRST and departureEnd for LAST on a single-direction runway."
    )
    public var closedEnd: String?

    /// The stated displacement of this runway's threshold.
    @Guide(description: "Stated threshold displacement (THR DSPLCD, DTHR) or relocation.")
    public var thresholdDisplacement: Length?

    /// Declared distances as stated for this runway direction.
    @Guide(description: "Declared distances stated for this single runway direction.")
    public var declaredDistances: DeclaredDistances?

    /// A runway condition report (FICON or ICAO GRF).
    public var surfaceCondition: SurfaceCondition?

    /// An obstacle in the runway environment.
    public var obstacle: Obstacle?

    /// Creates an effect.
    public init(
      runway: String?,
      closure: Closure,
      closedLength: Length? = nil,
      closedEnd: String? = nil,
      thresholdDisplacement: Length? = nil,
      declaredDistances: DeclaredDistances? = nil,
      surfaceCondition: SurfaceCondition? = nil,
      obstacle: Obstacle? = nil
    ) {
      self.runway = runway
      self.closure = closure
      self.closedLength = closedLength
      self.closedEnd = closedEnd
      self.thresholdDisplacement = thresholdDisplacement
      self.declaredDistances = declaredDistances
      self.surfaceCondition = surfaceCondition
      self.obstacle = obstacle
    }
  }

  /// What an effect states about runway closure.
  @Generable
  public enum Closure: String, Codable, Sendable {
    /// The effect states no closure.
    case none
    /// The runway is closed.
    case full
    /// A stated portion of the runway is closed.
    case partial
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

  /// Units a runway length is stated in.
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

  /// Declared distances for one runway direction; each is `nil` unless stated with a unit.
  @Generable(representNilExplicitlyInGeneratedContent: true)
  public struct DeclaredDistances: Codable, Sendable, Equatable {
    // swiftlint:disable identifier_name
    /// Take-off run available.
    public var TORA: Length?
    /// Take-off distance available.
    public var TODA: Length?
    /// Accelerate-stop distance available.
    public var ASDA: Length?
    /// Landing distance available.
    public var LDA: Length?
    // swiftlint:enable identifier_name

    /// Creates declared distances.
    public init(TORA: Length?, TODA: Length?, ASDA: Length?, LDA: Length?) {
      self.TORA = TORA
      self.TODA = TODA
      self.ASDA = ASDA
      self.LDA = LDA
    }
  }

  /// A runway condition report.
  @Generable(representNilExplicitlyInGeneratedContent: true)
  public struct SurfaceCondition: Codable, Sendable, Equatable {
    /// Runway condition codes as reported, in reporting order.
    @Guide(
      description:
        "Codes as reported, one per third: \"5/5/3\" → [5, 5, 3]. Null when none reported.",
      .maximumCount(3),
      .element(.range(0...6))
    )
    public var rwyCC: [Int]?

    /// Contaminants reported for the runway surface covered by the report.
    @Guide(
      description:
        "Contaminants reported. Exclude treatments, cleared width, REMAINDER and braking action.",
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

    /// Which runway third (in reporting order) the contaminant was reported for.
    @Guide(
      description:
        "1, 2 or 3 when the report lists thirds separated by commas; null for the whole runway.",
      .range(1...3)
    )
    public var runwayThird: Int?

    /// The stated coverage percentage.
    @Guide(
      description: "Stated percentage (40 PCT → 40). PATCHY and THIN are null.",
      .range(0...100)
    )
    public var coveragePercent: Int?

    /// The stated depth of the (top layer of the) contaminant.
    public var depth: Depth?

    /// Creates a contaminant.
    public init(type: ContaminantType, runwayThird: Int?, coveragePercent: Int?, depth: Depth?) {
      self.type = type
      self.runwayThird = runwayThird
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
    /// Anything else (mud, ash, rubber).
    case other
  }
  // swiftlint:enable raw_value_for_camel_cased_codable_enum

  /// An obstacle as reported.
  @Generable(representNilExplicitlyInGeneratedContent: true)
  public struct Obstacle: Codable, Sendable, Equatable {
    /// Height above ground: stated as AGL, or labelled HEIGHT or HGT without AMSL or MSL.
    @Guide(description: "Height stated as AGL, or labelled HEIGHT/HGT without AMSL/MSL.")
    public var heightAGL: Length?

    /// Elevation above sea level: stated as MSL or AMSL, or labelled ELEVATION or ELEV.
    @Guide(
      description:
        "Height stated as MSL/AMSL, or labelled ELEVATION/ELEV. In \"<n>FT (<n>FT AGL)\" the first height is MSL."
    )
    public var heightMSL: Length?

    /// Stated distance from ``distanceReference``.
    public var distance: Distance?

    /// What the distance is measured from, as stated.
    @Guide(description: "As stated: \"RWY 27 THR\", \"ARP\", \"JFK\".")
    public var distanceReference: String?

    /// A numeric bearing from the reference, when stated.
    @Guide(description: "Numeric bearing only; compass words like WNW are null.")
    public var bearingDegrees: Double?

    /// Stated position's latitude in decimal degrees, north positive.
    @Guide(
      description: "Stated DMS position in decimal degrees, north positive. Never from the Q-line.",
      .range(-90...90)
    )
    public var latitude: Double?

    /// Stated position's longitude in decimal degrees, east positive.
    @Guide(
      description: "Stated DMS position in decimal degrees, east positive. Never from the Q-line.",
      .range(-180...180)
    )
    public var longitude: Double?

    /// Creates an obstacle.
    public init(
      heightAGL: Length? = nil,
      heightMSL: Length? = nil,
      distance: Distance? = nil,
      distanceReference: String? = nil,
      bearingDegrees: Double? = nil,
      latitude: Double? = nil,
      longitude: Double? = nil
    ) {
      self.heightAGL = heightAGL
      self.heightMSL = heightMSL
      self.distance = distance
      self.distanceReference = distanceReference
      self.bearingDegrees = bearingDegrees
      self.latitude = latitude
      self.longitude = longitude
    }
  }
}
