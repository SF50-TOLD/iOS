public import Foundation

/// What a formatted NOTAM report states about runway performance: the surface condition of each
/// runway a condition report covers, or the obstacle an obstacle report describes.
///
/// It records what the report states, in the units it states it, and never a derived value: the
/// governing runway condition code and the contamination category are the app's to work out.
public struct FormattedReport: Sendable, Equatable {
  /// One entry per runway the report covers; an obstacle tied to no runway has an entry of its own.
  public var effects: [RunwayEffect]

  /// Creates a report.
  public init(effects: [RunwayEffect]) {
    self.effects = effects
  }
}

extension FormattedReport {
  /// What a report states about one runway.
  public struct RunwayEffect: Sendable, Equatable {
    /// The designator, zero-padded, with a pair written with a slash (`09R`, `09R/27L`); `nil` for
    /// an obstacle off no runway end.
    public var runway: String?

    /// The runway's surface condition, from a runway condition report.
    public var surfaceCondition: SurfaceCondition?

    /// An obstacle, from an obstacle report.
    public var obstacle: Obstacle?

    /// Creates an effect.
    public init(
      runway: String?,
      surfaceCondition: SurfaceCondition? = nil,
      obstacle: Obstacle? = nil
    ) {
      self.runway = runway
      self.surfaceCondition = surfaceCondition
      self.obstacle = obstacle
    }
  }

  /// A runway surface condition, as a FICON, RSC or SNOWTAM reports it.
  public struct SurfaceCondition: Sendable, Equatable {
    /// Runway condition codes, one per third in reporting order; `nil` when none are reported.
    public var rwyCC: [Int]?

    /// The contaminants reported on the runway surface.
    public var contaminants: [Contaminant]

    /// Creates a surface condition.
    public init(rwyCC: [Int]?, contaminants: [Contaminant]) {
      self.rwyCC = rwyCC
      self.contaminants = contaminants
    }
  }

  /// One reported contaminant.
  public struct Contaminant: Sendable, Equatable {
    /// The FAA AC 150/5200-30D contaminant.
    public var type: ContaminantType

    /// The runway third, in reporting order, the contaminant is reported for; `nil` for the whole
    /// runway.
    public var runwayThird: Int?

    /// The stated coverage percentage; `nil` when none is stated, or for `PATCHY` and `THIN`.
    public var coveragePercent: Int?

    /// The stated depth of the contaminant, or of its top layer.
    public var depth: Measurement<UnitLength>?

    /// Creates a contaminant.
    public init(
      type: ContaminantType,
      runwayThird: Int?,
      coveragePercent: Int?,
      depth: Measurement<UnitLength>?
    ) {
      self.type = type
      self.runwayThird = runwayThird
      self.coveragePercent = coveragePercent
      self.depth = depth
    }
  }

  /// FAA AC 150/5200-30D contaminants, as runway condition reports write them.
  public enum ContaminantType: Sendable {
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

  /// An obstacle, as an FAA obstacle report describes it.
  public struct Obstacle: Sendable, Equatable {
    /// Height above ground level; `nil` when reported unknown.
    public var heightAGL: Measurement<UnitLength>?

    /// Elevation above mean sea level; `nil` when reported unknown.
    public var heightMSL: Measurement<UnitLength>?

    /// Distance from ``distanceReference``.
    public var distance: Measurement<UnitLength>

    /// What the distance is measured from, as written (`JFK`, `APCH END RWY 03L`).
    public var distanceReference: String

    /// The compass direction from ``distanceReference``.
    public var direction: CompassPoint

    /// The runway end ``distanceReference`` names, when it names nothing else
    /// (`APCH END RWY 03L`, `DEP END RWY 30`).
    public var runwayEnd: RunwayEnd?

    /// Creates an obstacle.
    public init(
      heightAGL: Measurement<UnitLength>?,
      heightMSL: Measurement<UnitLength>?,
      distance: Measurement<UnitLength>,
      distanceReference: String,
      direction: CompassPoint,
      runwayEnd: RunwayEnd?
    ) {
      self.heightAGL = heightAGL
      self.heightMSL = heightMSL
      self.distance = distance
      self.distanceReference = distanceReference
      self.direction = direction
      self.runwayEnd = runwayEnd
    }
  }

  /// One end of a runway, as an obstacle report names it.
  public struct RunwayEnd: Sendable, Equatable {
    /// The runway direction whose end it is, normalized (`03L`).
    public var runway: String

    /// Which end of that runway direction it is.
    public var end: End

    /// Creates a runway end.
    public init(runway: String, end: End) {
      self.runway = runway
      self.end = end
    }

    /// An end of a runway direction.
    public enum End: Sendable, Equatable {
      /// The approach end (`APCH END`): the threshold aircraft landing in that direction cross.
      case approach
      /// The departure end (`DEP END`): where aircraft taking off in that direction leave the
      /// runway.
      case departure
    }
  }

  /// A direction as one of the 16 points of the compass.
  public enum CompassPoint: String, Sendable, CaseIterable {
    // swiftlint:disable identifier_name
    case N, NNE, NE, ENE, E, ESE, SE, SSE, S, SSW, SW, WSW, W, WNW, NW, NNW
    // swiftlint:enable identifier_name

    /// The point's bearing in degrees, clockwise from north.
    public var degrees: Double {
      Double(Self.allCases.firstIndex(of: self) ?? 0) * 360 / Double(Self.allCases.count)
    }
  }
}
