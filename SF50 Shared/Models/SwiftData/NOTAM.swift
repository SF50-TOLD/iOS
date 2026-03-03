import Foundation
import SwiftData

/// Location of runway shortening relative to the operation direction.
///
/// When a portion of a runway is closed, the closure can be at either end.
/// This affects visualization but not the available distance calculation.
public enum ShorteningLocation: String, Codable, CaseIterable, Sendable {
  /// Shortening at the threshold/approach end of the runway.
  ///
  /// For takeoff: The start of the takeoff roll is pushed further down the runway.
  /// For landing: The touchdown zone is pushed further down the runway.
  case thresholdEnd = "threshold_end"

  /// Shortening at the departure end of the runway (DER).
  ///
  /// For takeoff: The start point is unchanged, but the runway ends earlier.
  /// For landing: The touchdown zone is unchanged, but the runway ends earlier.
  case departureEnd = "departure_end"
}

/// Notice to Airmen (NOTAM) affecting runway performance.
///
/// ``NOTAM`` represents temporary conditions that affect runway performance calculations,
/// including contamination (ice, snow, water), displaced thresholds, and obstacles.
@Model
public final class NOTAM {
  private var _contaminationType: String?
  private var _contaminationDepth: Double  // meters
  private var _rwyCC: UInt8?
  private var _takeoffDistanceShortening: Double  // meters
  private var _landingDistanceShortening: Double  // meters
  private var _obstacleHeight: Double  // meters
  private var _obstacleDistance: Double  // meters
  private var _takeoffShorteningLocation: String?
  private var _landingShorteningLocation: String?

  @Relationship(deleteRule: .nullify)
  public var runway: Runway

  /// Runway surface contamination (ice, snow, slush, water)
  public var contamination: Contamination? {
    get { .init(type: _contaminationType, depth: _contaminationDepth, rwyCC: _rwyCC) }
    set {
      _contaminationType = newValue?.type
      _contaminationDepth = newValue?.depth ?? 0
      _rwyCC = newValue?.rwyCC
    }
  }

  /// Reduction in takeoff distance available due to displaced threshold
  public var takeoffDistanceShortening: Measurement<UnitLength> {
    get { .init(value: _takeoffDistanceShortening, unit: .meters) }
    set { _takeoffDistanceShortening = newValue.converted(to: .meters).value }
  }

  /// Reduction in landing distance available due to displaced threshold
  public var landingDistanceShortening: Measurement<UnitLength> {
    get { .init(value: _landingDistanceShortening, unit: .meters) }
    set { _landingDistanceShortening = newValue.converted(to: .meters).value }
  }

  /// Height of obstacle above runway surface
  public var obstacleHeight: Measurement<UnitLength> {
    get { .init(value: _obstacleHeight, unit: .meters) }
    set { _obstacleHeight = newValue.converted(to: .meters).value }
  }

  /// Distance from runway threshold to obstacle
  public var obstacleDistance: Measurement<UnitLength> {
    get { .init(value: _obstacleDistance, unit: .meters) }
    set { _obstacleDistance = newValue.converted(to: .meters).value }
  }

  /// Location of takeoff distance shortening (threshold end or departure end).
  ///
  /// Defaults to `.departureEnd` for existing NOTAMs without this value set.
  public var takeoffShorteningLocation: ShorteningLocation {
    get {
      _takeoffShorteningLocation.flatMap { ShorteningLocation(rawValue: $0) } ?? .departureEnd
    }
    set { _takeoffShorteningLocation = newValue.rawValue }
  }

  /// Location of landing distance shortening (threshold end or departure end).
  ///
  /// Defaults to `.departureEnd` for existing NOTAMs without this value set.
  public var landingShorteningLocation: ShorteningLocation {
    get {
      _landingShorteningLocation.flatMap { ShorteningLocation(rawValue: $0) } ?? .departureEnd
    }
    set { _landingShorteningLocation = newValue.rawValue }
  }

  /// Returns true if the NOTAM has no restrictions set.
  public var isEmpty: Bool {
    return contamination == nil
      && takeoffDistanceShortening.value == 0
      && landingDistanceShortening.value == 0
      && obstacleHeight.value == 0
      && obstacleDistance.value == 0
  }

  /// Creates a new NOTAM for a runway.
  public init(
    runway: Runway,
    contamination: Contamination? = nil,
    takeoffDistanceShortening: Measurement<UnitLength>? = nil,
    takeoffShorteningLocation: ShorteningLocation = .departureEnd,
    landingDistanceShortening: Measurement<UnitLength>? = nil,
    landingShorteningLocation: ShorteningLocation = .departureEnd,
    obstacleHeight: Measurement<UnitLength>? = nil,
    obstacleDistance: Measurement<UnitLength>? = nil
  ) {
    self.runway = runway
    _contaminationType = contamination?.type
    _contaminationDepth = contamination?.depth ?? 0
    _rwyCC = contamination?.rwyCC
    _takeoffDistanceShortening = takeoffDistanceShortening?.converted(to: .meters).value ?? 0
    _takeoffShorteningLocation = takeoffShorteningLocation.rawValue
    _landingDistanceShortening = landingDistanceShortening?.converted(to: .meters).value ?? 0
    _landingShorteningLocation = landingShorteningLocation.rawValue
    _obstacleHeight = obstacleHeight?.converted(to: .meters).value ?? 0
    _obstacleDistance = obstacleDistance?.converted(to: .meters).value ?? 0
  }

  /// Clears NOTAM restrictions for the specified operation type.
  public func clearFor(operation: Operation) {
    switch operation {
      case .takeoff:
        takeoffDistanceShortening = .init(value: 0, unit: .feet)
        takeoffShorteningLocation = .departureEnd
        obstacleHeight = .init(value: 0, unit: .feet)
        obstacleDistance = .init(value: 0, unit: .nauticalMiles)
      case .landing:
        landingDistanceShortening = .init(value: 0, unit: .feet)
        landingShorteningLocation = .departureEnd
        contamination = nil
    }
  }
}

/// Runway surface contamination type and depth.
///
/// ``Contamination`` represents various runway surface conditions that degrade
/// braking performance. Contamination data is used to apply performance penalties
/// according to the AFM contaminated runway tables.
public enum Contamination: Sendable, Hashable {
  /// Standing water or slush on the runway surface
  case waterOrSlush(depth: Measurement<UnitLength>)

  /// Slush or wet snow on the runway surface
  case slushOrWetSnow(depth: Measurement<UnitLength>)

  /// Dry snow covering the runway
  case drySnow

  /// Compacted snow or ice on the runway
  case compactSnow

  /// Wet runway surface
  case wetRunway

  /// Runway Condition Code (AC 91-79B) with landing distance factor
  case rwyCC(UInt8)

  /// Raw type string for persistence.
  var type: String {
    switch self {
      case .waterOrSlush: ContaminationType.waterOrSlush.rawValue
      case .slushOrWetSnow: ContaminationType.slushOrWetSnow.rawValue
      case .drySnow: ContaminationType.drySnow.rawValue
      case .compactSnow: ContaminationType.compactSnow.rawValue
      case .wetRunway: ContaminationType.wetRunway.rawValue
      case .rwyCC: ContaminationType.rwyCC.rawValue
    }
  }

  /// Contamination depth in meters for types that require it.
  var depth: Double? {
    switch self {
      case .waterOrSlush(let depth): depth.converted(to: .meters).value
      case .slushOrWetSnow(let depth): depth.converted(to: .meters).value
      case .drySnow, .compactSnow, .wetRunway, .rwyCC: nil
    }
  }

  /// Runway Condition Code (1–6) if this is an `.rwyCC` contamination, nil otherwise.
  var rwyCC: UInt8? {
    if case .rwyCC(let code) = self { code } else { nil }
  }

  /// Creates contamination from persistence storage values.
  init?(type: String?, depth: Double?, rwyCC: UInt8? = nil) {
    guard let type, let typeEnum = ContaminationType(rawValue: type) else { return nil }

    switch typeEnum {
      case .waterOrSlush:
        guard let depth else { return nil }
        self = .waterOrSlush(depth: .init(value: depth, unit: .meters))
      case .slushOrWetSnow:
        guard let depth else { return nil }
        self = .slushOrWetSnow(depth: .init(value: depth, unit: .meters))
      case .drySnow:
        self = .drySnow
      case .compactSnow:
        self = .compactSnow
      case .wetRunway:
        self = .wetRunway
      case .rwyCC:
        guard let rwyCC, (1...6).contains(rwyCC) else { return nil }
        self = .rwyCC(rwyCC)
    }
  }

  /// Raw string values for persistence.
  enum ContaminationType: String {
    /// Standing water or slush
    case waterOrSlush
    /// Slush or wet snow
    case slushOrWetSnow
    /// Dry snow coverage
    case drySnow
    /// Compacted snow or ice
    case compactSnow
    /// Wet runway surface
    case wetRunway
    /// Runway Condition Code
    case rwyCC
  }
}
