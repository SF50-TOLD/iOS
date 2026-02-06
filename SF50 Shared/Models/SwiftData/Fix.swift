import CoreLocation
import Foundation
import SwiftData

/// A navigational fix in an instrument procedure.
///
/// ``Fix`` represents a waypoint or intersection in a departure procedure
/// (SID) or missed approach procedure. Each fix has a ``legType`` describing
/// the path geometry used to reach it, and may have an ``altitudeRestriction``
/// specifying minimum, maximum, or exact crossing altitudes.
@Model
public final class Fix {
  /// Fix identifier (e.g., "ORCKA", "REBAS")
  public var identifier: String

  private var _latitude: Double  // decimal degrees
  private var _longitude: Double  // decimal degrees

  // Altitude restriction stored as type + values (following NOTAM/Contamination pattern)
  private var _altitudeRestrictionType: String?
  private var _altitudeMin: Double?  // meters
  private var _altitudeMax: Double?  // meters (only used for "between")

  // Leg type stored as raw values for SwiftData persistence
  private var _legType: String  // discriminator (e.g., "trackToFix")
  private var _legCourse: Double?  // degrees
  private var _legTurnDirection: String?  // "left", "right", "either"
  private var _legArcRadius: Double?  // nautical miles

  /// Position in the departure procedure fix sequence (0-indexed)
  public var sequenceIndex: Int

  /// The departure procedure this fix belongs to
  @Relationship(deleteRule: .nullify, inverse: \DepartureProcedure.fixes)
  public var departureProcedure: DepartureProcedure?

  /// The approach procedure this fix belongs to (for missed approach fixes)
  @Relationship(deleteRule: .nullify, inverse: \ApproachProcedure.missedApproachFixes)
  public var approachProcedure: ApproachProcedure?

  /// Fix latitude in degrees
  public var latitude: Measurement<UnitAngle> {
    get { .init(value: _latitude, unit: .degrees) }
    set { _latitude = newValue.converted(to: .degrees).value }
  }

  /// Fix longitude in degrees
  public var longitude: Measurement<UnitAngle> {
    get { .init(value: _longitude, unit: .degrees) }
    set { _longitude = newValue.converted(to: .degrees).value }
  }

  /// CoreLocation coordinate for the fix
  public var coordinate: CLLocationCoordinate2D {
    .init(
      latitude: latitude.converted(to: .degrees).value,
      longitude: longitude.converted(to: .degrees).value
    )
  }

  /// Altitude restriction at this fix
  public var altitudeRestriction: AltitudeRestriction? {
    get {
      .init(
        type: _altitudeRestrictionType,
        altitudeMin: _altitudeMin,
        altitudeMax: _altitudeMax
      )
    }
    set {
      _altitudeRestrictionType = newValue?.type
      _altitudeMin = newValue?.altitudeMin
      _altitudeMax = newValue?.altitudeMax
    }
  }

  /// Leg type geometry for plotting the path to this fix.
  public var legType: LegType {
    get {
      guard let discriminator = LegTypeCodable.LegTypeDiscriminator(rawValue: _legType) else {
        fatalError("Unknown leg type discriminator: \(_legType)")
      }
      return LegType(
        from: LegTypeCodable(
          type: discriminator,
          course: _legCourse,
          turnDirection: _legTurnDirection,
          arcRadius: _legArcRadius
        )
      )
    }
    set {
      let decomposed = Self.decomposeLegType(newValue)
      _legType = decomposed.type
      _legCourse = decomposed.course
      _legTurnDirection = decomposed.turnDirection
      _legArcRadius = decomposed.arcRadius
    }
  }

  /// Creates a new fix.
  ///
  /// - Parameters:
  ///   - identifier: Fix identifier.
  ///   - latitude: Fix latitude.
  ///   - longitude: Fix longitude.
  ///   - altitudeRestriction: Altitude restriction at this fix, if any.
  ///   - legType: Leg type geometry for plotting.
  ///   - sequenceIndex: Position in the procedure fix sequence.
  ///   - departureProcedure: The departure procedure this fix belongs to.
  ///   - approachProcedure: The approach procedure this fix belongs to.
  public init(
    identifier: String,
    latitude: Measurement<UnitAngle>,
    longitude: Measurement<UnitAngle>,
    altitudeRestriction: AltitudeRestriction? = nil,
    legType: LegType,
    sequenceIndex: Int,
    departureProcedure: DepartureProcedure? = nil,
    approachProcedure: ApproachProcedure? = nil
  ) {
    self.identifier = identifier
    _latitude = latitude.converted(to: .degrees).value
    _longitude = longitude.converted(to: .degrees).value
    _altitudeRestrictionType = altitudeRestriction?.type
    _altitudeMin = altitudeRestriction?.altitudeMin
    _altitudeMax = altitudeRestriction?.altitudeMax
    // Decompose legType into backing fields inline (can't use computed setter before init completes)
    let decomposed = Self.decomposeLegType(legType)
    _legType = decomposed.type
    _legCourse = decomposed.course
    _legTurnDirection = decomposed.turnDirection
    _legArcRadius = decomposed.arcRadius
    self.sequenceIndex = sequenceIndex
    self.departureProcedure = departureProcedure
    self.approachProcedure = approachProcedure
  }

  /// Creates a new fix from a codable leg type representation.
  ///
  /// Convenience initializer for the ``NavDataLoader`` import path.
  public convenience init(
    identifier: String,
    latitude: Measurement<UnitAngle>,
    longitude: Measurement<UnitAngle>,
    altitudeRestriction: AltitudeRestriction? = nil,
    legType: LegTypeCodable,
    sequenceIndex: Int,
    departureProcedure: DepartureProcedure? = nil,
    approachProcedure: ApproachProcedure? = nil
  ) {
    self.init(
      identifier: identifier,
      latitude: latitude,
      longitude: longitude,
      altitudeRestriction: altitudeRestriction,
      legType: LegType(from: legType),
      sequenceIndex: sequenceIndex,
      departureProcedure: departureProcedure,
      approachProcedure: approachProcedure
    )
  }

  /// Decomposes a ``LegType`` into raw backing field values.
  ///
  /// Used by `init` to avoid accessing `self` before all stored properties are initialized.
  private static func decomposeLegType(
    _ legType: LegType
  ) -> (type: String, course: Double?, turnDirection: String?, arcRadius: Double?) {
    switch legType {
      case .initialFix:
        return ("initialFix", nil, nil, nil)
      case .trackToFix(let course):
        return ("trackToFix", course?.converted(to: .degrees).value, nil, nil)
      case .courseToFix(let course):
        return ("courseToFix", course.converted(to: .degrees).value, nil, nil)
      case .directToFix:
        return ("directToFix", nil, nil, nil)
      case .radiusToFix(let arcRadius, let course):
        return (
          "radiusToFix", course.converted(to: .degrees).value, nil,
          arcRadius.converted(to: .nauticalMiles).value
        )
      case .arcToFix(let arcRadius, let course):
        return (
          "arcToFix", course.converted(to: .degrees).value, nil,
          arcRadius.converted(to: .nauticalMiles).value
        )
      case .holdToFix(let course, let turnDirection):
        return ("holdToFix", course.converted(to: .degrees).value, turnDirection.rawValue, nil)
      case .holdToAltitude(let course, let turnDirection):
        return ("holdToAltitude", course.converted(to: .degrees).value, turnDirection.rawValue, nil)
      case .holdManual(let course, let turnDirection):
        return ("holdManual", course.converted(to: .degrees).value, turnDirection.rawValue, nil)
      case .fixToAltitude(let course):
        return ("fixToAltitude", course.converted(to: .degrees).value, nil, nil)
      case .trackFromFixDistance(let course):
        return ("trackFromFixDistance", course.converted(to: .degrees).value, nil, nil)
      case .trackFromFixDME(let course):
        return ("trackFromFixDME", course.converted(to: .degrees).value, nil, nil)
      case .courseToAltitude(let course):
        return ("courseToAltitude", course.converted(to: .degrees).value, nil, nil)
      case .courseToDME(let course):
        return ("courseToDME", course.converted(to: .degrees).value, nil, nil)
      case .courseToIntercept(let course):
        return ("courseToIntercept", course.converted(to: .degrees).value, nil, nil)
      case .courseToRadial(let course):
        return ("courseToRadial", course.converted(to: .degrees).value, nil, nil)
      case .headingToAltitude(let heading):
        return ("headingToAltitude", heading.converted(to: .degrees).value, nil, nil)
      case .headingToDME(let heading):
        return ("headingToDME", heading.converted(to: .degrees).value, nil, nil)
      case .headingToIntercept(let heading):
        return ("headingToIntercept", heading.converted(to: .degrees).value, nil, nil)
      case .headingToRadial(let heading):
        return ("headingToRadial", heading.converted(to: .degrees).value, nil, nil)
      case .procedureTurn(let course, let turnDirection):
        return ("procedureTurn", course.converted(to: .degrees).value, turnDirection.rawValue, nil)
    }
  }
}
