import CoreLocation
import Foundation
import SwiftData

/// A leg in an instrument procedure.
///
/// ``Leg`` represents a path segment in a departure procedure (SID) or missed
/// approach procedure. Each leg has a ``legType`` describing the path geometry,
/// a fix identifier and coordinates for the termination point, and may have an
/// ``altitudeRestriction`` specifying minimum, maximum, or exact crossing altitudes.
@Model
public final class Leg {
  /// Fix identifier (e.g., "ORCKA", "REBAS"). Nil for *ToAltitude legs with no fix.
  public var identifier: String?

  private var _latitude: Double?  // decimal degrees
  private var _longitude: Double?  // decimal degrees

  // Altitude restriction stored as type + values (following NOTAM/Contamination pattern)
  private var _altitudeRestrictionType: String?
  private var _altitudeMin: Double?  // meters
  private var _altitudeMax: Double?  // meters (only used for "between")

  // Leg type stored as raw values for SwiftData persistence
  private var _legType: String  // discriminator (e.g., "trackToFix")
  private var _legCourse: Double?  // degrees
  private var _legTurnDirection: String?  // "left", "right", "either"
  private var _legArcRadius: Double?  // nautical miles

  // DME distance stored as raw value for SwiftData persistence
  private var _dmeDistanceNM: Double?  // nautical miles

  // Radial bearing stored as raw value for SwiftData persistence
  private var _thetaDeg: Double?  // magnetic degrees from navaid

  /// Position in the procedure leg sequence (0-indexed)
  public var sequenceIndex: Int

  /// The procedure segment this leg belongs to
  @Relationship(deleteRule: .nullify, inverse: \ProcedureSegment.legs)
  public var segment: ProcedureSegment?

  /// The recommended DME navaid for this leg (nil if not a DME leg)
  @Relationship(deleteRule: .noAction, inverse: \Navaid.legs)
  public var navaid: Navaid?

  /// Fix latitude in degrees. Nil for legs with no fix (e.g., CA/VA).
  public var latitude: Measurement<UnitAngle>? {
    get { _latitude.map { .init(value: $0, unit: .degrees) } }
    set { _latitude = newValue?.converted(to: .degrees).value }
  }

  /// Fix longitude in degrees. Nil for legs with no fix (e.g., CA/VA).
  public var longitude: Measurement<UnitAngle>? {
    get { _longitude.map { .init(value: $0, unit: .degrees) } }
    set { _longitude = newValue?.converted(to: .degrees).value }
  }

  /// CoreLocation coordinate for the fix. Nil for legs with no fix.
  public var coordinate: CLLocationCoordinate2D? {
    guard let _latitude, let _longitude else { return nil }
    return .init(latitude: _latitude, longitude: _longitude)
  }

  /// DME termination distance from the recommended navaid (nil if not a DME leg)
  public var dmeDistance: Measurement<UnitLength>? {
    get { _dmeDistanceNM.map { .init(value: $0, unit: .nauticalMiles) } }
    set { _dmeDistanceNM = newValue?.converted(to: .nauticalMiles).value }
  }

  /// Magnetic radial bearing from the navaid (nil if not a radial leg)
  public var theta: Measurement<UnitAngle>? {
    get { _thetaDeg.map { .init(value: $0, unit: .degrees) } }
    set { _thetaDeg = newValue?.converted(to: .degrees).value }
  }

  /// Altitude restriction at this leg's termination point
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

  /// Whether this leg has the data needed for its leg type to be resolved to a path.
  ///
  /// Checks that required fields (coordinates, navaid, DME distance, altitude restriction)
  /// are present for the specific leg type geometry.
  var hasRequiredData: Bool {
    switch legType {
      case .initialFix, .trackToFix, .courseToFix, .directToFix,
        .holdToFix, .holdToAltitude, .holdManual, .procedureTurn,
        .radiusToFix, .arcToFix:
        return coordinate != nil
      case .fixToAltitude, .courseToAltitude, .headingToAltitude:
        return altitudeRestriction != nil
      case .courseToDME, .headingToDME:
        return navaid != nil && dmeDistance != nil
      case .trackFromFixDME:
        return coordinate != nil && navaid != nil && dmeDistance != nil
      case .trackFromFixDistance:
        return coordinate != nil && dmeDistance != nil
      case .courseToIntercept, .headingToIntercept:
        return true
      case .courseToRadial, .headingToRadial:
        return navaid != nil && theta != nil
    }
  }

  /// Creates a new leg.
  ///
  /// - Parameters:
  ///   - identifier: Fix identifier (nil for *ToAltitude legs with no fix).
  ///   - latitude: Fix latitude (nil for legs with no fix).
  ///   - longitude: Fix longitude (nil for legs with no fix).
  ///   - altitudeRestriction: Altitude restriction at this leg's termination point, if any.
  ///   - legType: Leg type geometry for plotting.
  ///   - sequenceIndex: Position in the procedure leg sequence.
  ///   - segment: The procedure segment this leg belongs to.
  ///   - navaid: The recommended DME navaid, if applicable.
  ///   - dmeDistance: DME termination distance, if applicable.
  public init(
    identifier: String?,
    latitude: Measurement<UnitAngle>?,
    longitude: Measurement<UnitAngle>?,
    altitudeRestriction: AltitudeRestriction? = nil,
    legType: LegType,
    sequenceIndex: Int,
    segment: ProcedureSegment? = nil,
    navaid: Navaid? = nil,
    dmeDistance: Measurement<UnitLength>? = nil,
    theta: Measurement<UnitAngle>? = nil
  ) {
    self.identifier = identifier
    _latitude = latitude?.converted(to: .degrees).value
    _longitude = longitude?.converted(to: .degrees).value
    _altitudeRestrictionType = altitudeRestriction?.type
    _altitudeMin = altitudeRestriction?.altitudeMin
    _altitudeMax = altitudeRestriction?.altitudeMax
    _dmeDistanceNM = dmeDistance?.converted(to: .nauticalMiles).value
    _thetaDeg = theta?.converted(to: .degrees).value
    // Decompose legType into backing fields inline (can't use computed setter before init completes)
    let decomposed = Self.decomposeLegType(legType)
    _legType = decomposed.type
    _legCourse = decomposed.course
    _legTurnDirection = decomposed.turnDirection
    _legArcRadius = decomposed.arcRadius
    self.sequenceIndex = sequenceIndex
    self.segment = segment
    self.navaid = navaid
  }

  /// Creates a new leg from a codable leg type representation.
  ///
  /// Convenience initializer for the ``NavDataLoader`` import path.
  public convenience init(
    identifier: String?,
    latitude: Measurement<UnitAngle>?,
    longitude: Measurement<UnitAngle>?,
    altitudeRestriction: AltitudeRestriction? = nil,
    legType: LegTypeCodable,
    sequenceIndex: Int,
    segment: ProcedureSegment? = nil,
    navaid: Navaid? = nil,
    dmeDistance: Measurement<UnitLength>? = nil,
    theta: Measurement<UnitAngle>? = nil
  ) {
    self.init(
      identifier: identifier,
      latitude: latitude,
      longitude: longitude,
      altitudeRestriction: altitudeRestriction,
      legType: LegType(from: legType),
      sequenceIndex: sequenceIndex,
      segment: segment,
      navaid: navaid,
      dmeDistance: dmeDistance,
      theta: theta
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
