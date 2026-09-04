public import Foundation
import MeasurementKit
import NavData

/// Sendable snapshot of NOTAM data for background performance calculations.
///
/// ``NOTAMInput`` is a value type that captures NOTAM data for use in
/// background actor contexts where the SwiftData ``NOTAM`` model cannot be accessed.
public struct NOTAMInput: Sendable, Equatable {
  /// Raw contamination type string for serialization
  public let contaminationType: String?

  /// Depth of contamination on the runway surface
  public let contaminationDepth: Measurement<UnitLength>

  /// Runway Condition Code (1–6) for RwyCC contamination type
  public let rwyCC: UInt8?

  /// Reduction in takeoff distance available
  public let takeoffDistanceShortening: Measurement<UnitLength>

  /// Reduction in landing distance available
  public let landingDistanceShortening: Measurement<UnitLength>

  /// Height of obstacle above runway
  public let obstacleHeight: Measurement<UnitLength>

  /// Distance from threshold to obstacle
  public let obstacleDistance: Measurement<UnitLength>

  /// Parsed contamination enum from type string and depth
  public var contamination: Contamination? {
    guard let type = contaminationType else { return nil }
    return Contamination(
      type: type,
      depth: contaminationDepth.converted(to: .meters).value,
      rwyCC: rwyCC
    )
  }

  /// Creates a snapshot from a SwiftData NOTAM model.
  /// - Parameter notam: The NOTAM to capture.
  public init(from notam: NOTAM) {
    self.contaminationType = notam.contamination?.type
    self.contaminationDepth = .init(value: notam.contamination?.depth ?? 0, unit: .meters)
    self.rwyCC = notam.contamination?.rwyCC
    self.takeoffDistanceShortening = notam.takeoffDistanceShortening
    self.landingDistanceShortening = notam.landingDistanceShortening
    self.obstacleHeight = notam.obstacleHeight
    self.obstacleDistance = notam.obstacleDistance
  }

  public init(
    contaminationType: String?,
    contaminationDepth: Measurement<UnitLength>,
    rwyCC: UInt8? = nil,
    takeoffDistanceShortening: Measurement<UnitLength>,
    landingDistanceShortening: Measurement<UnitLength>,
    obstacleHeight: Measurement<UnitLength>,
    obstacleDistance: Measurement<UnitLength>
  ) {
    self.contaminationType = contaminationType
    self.contaminationDepth = contaminationDepth
    self.rwyCC = rwyCC
    self.takeoffDistanceShortening = takeoffDistanceShortening
    self.landingDistanceShortening = landingDistanceShortening
    self.obstacleHeight = obstacleHeight
    self.obstacleDistance = obstacleDistance
  }
}

/// Sendable snapshot of Runway data for background performance calculations.
///
/// ``RunwayInput`` is a value type that captures runway data for use in
/// background actor contexts where the SwiftData ``Runway`` model cannot be accessed.
/// It includes all runway properties needed for performance calculations.
public struct RunwayInput: Identifiable, Hashable, Sendable, Comparable {
  // MARK: - Properties

  /// Unique identifier (runway name)
  public let id: String

  /// Runway threshold elevation
  public let elevation: Measurement<UnitLength>

  /// True heading of the runway
  public let trueHeading: Measurement<UnitAngle>

  /// Runway gradient as a fraction (positive = upslope)
  public let gradient: Float

  /// Total runway length
  public let length: Measurement<UnitLength>

  /// Declared takeoff run available (TORA)
  public let takeoffRun: Measurement<UnitLength>?

  /// Takeoff distance available, adjusted for NOTAMs
  public let takeoffDistance: Measurement<UnitLength>

  /// Declared landing distance available (LDA)
  public let landingDistance: Measurement<UnitLength>?

  /// Surface type of the runway
  public let surfaceType: SurfaceType

  /// Whether the runway has a turf surface
  public var isTurf: Bool { surfaceType.isTurf }

  /// Whether the runway has a grooved or PFC surface
  public var isGroovedOrPFC: Bool { surfaceType.isGroovedOrPFC }

  /// Active NOTAM snapshot if present
  public let notam: NOTAMInput?

  /// Magnetic variation at the airport
  public let airportVariation: Measurement<UnitAngle>

  /// Threshold crossing height for approach (nil if not available)
  public let thresholdCrossingHeight: Measurement<UnitLength>?

  /// Glidepath angle from ILS or PAPI/VASI (nil if not available)
  public let glidepathAngle: Measurement<UnitAngle>?

  /// Displaced threshold distance from runway end (nil if not displaced)
  public let displacedThresholdDistance: Measurement<UnitLength>?

  /// Runway designator (alias for id)
  public var name: String { id }

  // MARK: - Initialization

  /// Creates a snapshot from SwiftData Runway and Airport models.
  /// - Parameters:
  ///   - runway: The runway to capture.
  ///   - airport: The airport the runway belongs to.
  public init(from runway: Runway, airport: Airport) {
    self.id = runway.name
    self.elevation = runway.elevationOrAirportElevation
    self.trueHeading = runway.trueHeading
    self.gradient = runway.gradientOrBestGuess
    self.length = runway.length
    self.takeoffRun = runway.takeoffRun
    self.takeoffDistance = runway.notamedTakeoffDistance
    self.landingDistance = runway.landingDistance
    self.surfaceType = runway.surfaceType
    self.notam = runway.notam.map { NOTAMInput(from: $0) }
    self.airportVariation = airport.variation
    self.thresholdCrossingHeight = runway.thresholdCrossingHeight
    self.glidepathAngle = runway.glidepathAngle
    self.displacedThresholdDistance = runway.displacedThresholdDistance
  }

  public init(
    id: String,
    elevation: Measurement<UnitLength>,
    trueHeading: Measurement<UnitAngle>,
    gradient: Float,
    length: Measurement<UnitLength>,
    takeoffRun: Measurement<UnitLength>?,
    takeoffDistance: Measurement<UnitLength>,
    landingDistance: Measurement<UnitLength>?,
    surfaceType: SurfaceType = .paved,
    notam: NOTAMInput?,
    airportVariation: Measurement<UnitAngle>,
    thresholdCrossingHeight: Measurement<UnitLength>? = nil,
    glidepathAngle: Measurement<UnitAngle>? = nil,
    displacedThresholdDistance: Measurement<UnitLength>? = nil
  ) {
    self.id = id
    self.elevation = elevation
    self.trueHeading = trueHeading
    self.gradient = gradient
    self.length = length
    self.takeoffRun = takeoffRun
    self.takeoffDistance = takeoffDistance
    self.landingDistance = landingDistance
    self.surfaceType = surfaceType
    self.notam = notam
    self.airportVariation = airportVariation
    self.thresholdCrossingHeight = thresholdCrossingHeight
    self.glidepathAngle = glidepathAngle
    self.displacedThresholdDistance = displacedThresholdDistance
  }

  // MARK: - Type Methods

  // Comparable implementation for sorting
  public static func < (lhs: Self, rhs: Self) -> Bool {
    let num1 = Int(lhs.name.filter(\.isNumber)) ?? 0,
      num2 = Int(rhs.name.filter(\.isNumber)) ?? 0

    if num1 != num2 {
      return num1 < num2
    }

    // If numbers are equal, compare the letters
    let letter1 = lhs.name.filter(\.isLetter),
      letter2 = rhs.name.filter(\.isLetter)

    // Order: no letter < L < C < R
    let letterOrder = ["": 0, "L": 1, "C": 2, "R": 3],
      val1 = letterOrder[letter1] ?? 4,
      val2 = letterOrder[letter2] ?? 4

    return val1 < val2
  }

  // MARK: - Instance Methods

  public func hash(into hasher: inout Hasher) {
    hasher.combine(id)
  }

  /// Calculates headwind component for the given weather conditions.
  /// - Parameter conditions: The atmospheric conditions.
  /// - Returns: Headwind component (positive = headwind, negative = tailwind).
  public func headwind(conditions: Conditions) -> Measurement<UnitSpeed> {
    guard let windDirection = conditions.windDirection,
      let windSpeed = conditions.windSpeed
    else { return .zero }

    // Wind direction in METAR/TAF is in true degrees, runway heading is also true
    return windSpeed * cos(windDirection - trueHeading)
  }

  /// Creates a copy of this runway with contamination override applied
  public func withContamination(_ contamination: Contamination?) -> Self {
    let newNotam: NOTAMInput? =
      if let notam {
        // Create a new NOTAM with the contamination override but keep other values
        NOTAMInput(
          contaminationType: contamination?.type,
          contaminationDepth: .init(value: contamination?.depth ?? 0, unit: .meters),
          rwyCC: contamination?.rwyCC,
          takeoffDistanceShortening: notam.takeoffDistanceShortening,
          landingDistanceShortening: notam.landingDistanceShortening,
          obstacleHeight: notam.obstacleHeight,
          obstacleDistance: notam.obstacleDistance
        )
      } else if let contamination {
        // Create a new NOTAM with just the contamination
        NOTAMInput(
          contaminationType: contamination.type,
          contaminationDepth: .init(value: contamination.depth ?? 0, unit: .meters),
          rwyCC: contamination.rwyCC,
          takeoffDistanceShortening: .init(value: 0, unit: .meters),
          landingDistanceShortening: .init(value: 0, unit: .meters),
          obstacleHeight: .init(value: 0, unit: .meters),
          obstacleDistance: .init(value: 0, unit: .meters)
        )
      } else {
        nil
      }

    return Self(
      id: id,
      elevation: elevation,
      trueHeading: trueHeading,
      gradient: gradient,
      length: length,
      takeoffRun: takeoffRun,
      takeoffDistance: takeoffDistance,
      landingDistance: landingDistance,
      surfaceType: surfaceType,
      notam: newNotam,
      airportVariation: airportVariation,
      thresholdCrossingHeight: thresholdCrossingHeight,
      glidepathAngle: glidepathAngle,
      displacedThresholdDistance: displacedThresholdDistance
    )
  }
}

/// Sendable snapshot of Airport data for background performance calculations.
///
/// ``AirportInput`` is a value type that captures airport data for use in
/// background actor contexts where the SwiftData ``Airport`` model cannot be accessed.
public struct AirportInput: Sendable {
  /// Unique SwiftData record identifier
  public let recordID: String

  /// Airport location identifier (FAA LID or ICAO)
  public let locationID: String

  /// Airport name
  public let name: String

  /// Airport field elevation
  public let elevation: Measurement<UnitLength>

  /// Magnetic variation at the airport
  public let variation: Measurement<UnitAngle>

  /// Local timezone for the airport
  public let timeZone: TimeZone?

  /// Runways at this airport
  public let runways: [RunwayInput]

  /// Creates a snapshot from a SwiftData Airport model.
  /// - Parameter airport: The airport to capture.
  public init(from airport: Airport) {
    self.recordID = airport.recordID
    self.locationID = airport.locationID
    self.name = airport.name
    self.elevation = airport.elevation
    self.variation = airport.variation
    self.timeZone = airport.timeZone
    self.runways = airport.runways.map { RunwayInput(from: $0, airport: airport) }
  }
}
