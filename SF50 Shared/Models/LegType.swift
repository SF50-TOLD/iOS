import Foundation

/// The type of procedure leg geometry used for plotting a fix on a chart.
///
/// Each case bundles all the parameters needed to draw the leg's path.
/// Associated values use `Measurement` types for type-safe unit handling.
///
/// - Note: This enum does not conform to `Codable` directly because
///   `Measurement` lacks stable Codable output. Serialization is handled
///   by ``LegTypeCodable``.
public enum LegType: Sendable, Hashable {

  // MARK: Fix-terminated (straight line to fix)

  case initialFix
  case trackToFix(course: Measurement<UnitAngle>?)
  case courseToFix(course: Measurement<UnitAngle>)
  case directToFix

  // MARK: Arc to fix

  case radiusToFix(arcRadius: Measurement<UnitLength>, course: Measurement<UnitAngle>)
  case arcToFix(arcRadius: Measurement<UnitLength>, course: Measurement<UnitAngle>)

  // MARK: Hold patterns

  case holdToFix(course: Measurement<UnitAngle>, turnDirection: TurnDirection)
  case holdToAltitude(course: Measurement<UnitAngle>, turnDirection: TurnDirection)
  case holdManual(course: Measurement<UnitAngle>, turnDirection: TurnDirection)

  // MARK: Course/track from fix to termination

  case fixToAltitude(course: Measurement<UnitAngle>)
  case trackFromFixDistance(course: Measurement<UnitAngle>)
  case trackFromFixDME(course: Measurement<UnitAngle>)
  case courseToAltitude(course: Measurement<UnitAngle>)
  case courseToDME(course: Measurement<UnitAngle>)
  case courseToIntercept(course: Measurement<UnitAngle>)
  case courseToRadial(course: Measurement<UnitAngle>)

  // MARK: Heading to termination

  case headingToAltitude(heading: Measurement<UnitAngle>)
  case headingToDME(heading: Measurement<UnitAngle>)
  case headingToIntercept(heading: Measurement<UnitAngle>)
  case headingToRadial(heading: Measurement<UnitAngle>)

  // MARK: Special

  case procedureTurn(course: Measurement<UnitAngle>, turnDirection: TurnDirection)

  /// Turn direction for holds and procedure turns.
  ///
  /// Nested here to avoid collision with SwiftCIFP's `TurnDirection`.
  public enum TurnDirection: String, Codable, Sendable, Hashable {
    case left, right, either
  }
}

extension LegType {
  /// The magnetic course or heading associated with this leg type, if any.
  public var magneticCourse: Measurement<UnitAngle>? {
    switch self {
      case .courseToFix(let c), .trackToFix(let c?),
        .fixToAltitude(let c), .courseToAltitude(let c),
        .courseToDME(let c), .courseToIntercept(let c),
        .courseToRadial(let c), .trackFromFixDME(let c),
        .trackFromFixDistance(let c):
        return c
      case .headingToAltitude(let h), .headingToDME(let h),
        .headingToIntercept(let h), .headingToRadial(let h):
        return h
      default:
        return nil
    }
  }

  /// Whether this leg type can be resolved to a geographic path.
  public var isPlottable: Bool {
    switch self {
      case .initialFix, .trackToFix, .courseToFix, .directToFix,
        .radiusToFix, .arcToFix,
        .holdToFix, .holdToAltitude, .holdManual,
        .fixToAltitude, .trackFromFixDistance, .trackFromFixDME,
        .courseToAltitude, .courseToDME, .courseToIntercept, .courseToRadial,
        .headingToAltitude, .headingToDME, .headingToIntercept, .headingToRadial,
        .procedureTurn:
        return true
    }
  }

  /// Whether this leg type can only be plotted as the terminal (last) leg.
  ///
  /// Hold patterns and procedure turns are plotted as a direct-to-fix only when
  /// they are the final leg of the sequence.
  public var isTerminalOnly: Bool {
    switch self {
      case .holdToFix, .holdToAltitude, .holdManual, .procedureTurn:
        return true
      default:
        return false
    }
  }

  /// Whether this is a heading-based leg that does not establish a course intercept.
  ///
  /// After these legs the aircraft is at a position but not on any specific course,
  /// so a following `courseToFix` implies ATC radar vectoring.
  public var isNonInterceptHeading: Bool {
    switch self {
      case .headingToAltitude, .headingToDME, .headingToRadial:
        return true
      default:
        return false
    }
  }

  /// Whether this is a course-to-fix leg type.
  public var isCourseToFix: Bool {
    switch self {
      case .courseToFix:
        return true
      default:
        return false
    }
  }

  /// Creates a `LegType` from its codable representation.
  ///
  /// Converts raw `Double` values (degrees for angles, NM for distances)
  /// into `Measurement` types.
  public init(from codable: LegTypeCodable) {
    switch codable.type {
      case .initialFix:
        self = .initialFix
      case .directToFix:
        self = .directToFix
      case .trackToFix:
        self = .trackToFix(
          course: codable.course.map { .init(value: $0, unit: .degrees) }
        )
      case .courseToFix:
        self = .courseToFix(course: Self.requireCourse(codable))
      case .radiusToFix:
        self = .radiusToFix(
          arcRadius: Self.requireArcRadius(codable),
          course: Self.requireCourse(codable)
        )
      case .arcToFix:
        self = .arcToFix(
          arcRadius: Self.requireArcRadius(codable),
          course: Self.requireCourse(codable)
        )
      case .holdToFix:
        self = .holdToFix(
          course: Self.requireCourse(codable),
          turnDirection: Self.requireTurnDirection(codable)
        )
      case .holdToAltitude:
        self = .holdToAltitude(
          course: Self.requireCourse(codable),
          turnDirection: Self.requireTurnDirection(codable)
        )
      case .holdManual:
        self = .holdManual(
          course: Self.requireCourse(codable),
          turnDirection: Self.requireTurnDirection(codable)
        )
      case .fixToAltitude:
        self = .fixToAltitude(course: Self.requireCourse(codable))
      case .trackFromFixDistance:
        self = .trackFromFixDistance(course: Self.requireCourse(codable))
      case .trackFromFixDME:
        self = .trackFromFixDME(course: Self.requireCourse(codable))
      case .courseToAltitude:
        self = .courseToAltitude(course: Self.requireCourse(codable))
      case .courseToDME:
        self = .courseToDME(course: Self.requireCourse(codable))
      case .courseToIntercept:
        self = .courseToIntercept(course: Self.requireCourse(codable))
      case .courseToRadial:
        self = .courseToRadial(course: Self.requireCourse(codable))
      case .headingToAltitude:
        self = .headingToAltitude(heading: Self.requireCourse(codable))
      case .headingToDME:
        self = .headingToDME(heading: Self.requireCourse(codable))
      case .headingToIntercept:
        self = .headingToIntercept(heading: Self.requireCourse(codable))
      case .headingToRadial:
        self = .headingToRadial(heading: Self.requireCourse(codable))
      case .procedureTurn:
        self = .procedureTurn(
          course: Self.requireCourse(codable),
          turnDirection: Self.requireTurnDirection(codable)
        )
    }
  }

  private static func requireCourse(
    _ codable: LegTypeCodable
  ) -> Measurement<UnitAngle> {
    guard let course = codable.course else {
      fatalError("LegTypeCodable.\(codable.type) requires course")
    }
    return .init(value: course, unit: .degrees)
  }

  private static func requireArcRadius(
    _ codable: LegTypeCodable
  ) -> Measurement<UnitLength> {
    guard let arcRadius = codable.arcRadius else {
      fatalError("LegTypeCodable.\(codable.type) requires arcRadius")
    }
    return .init(value: arcRadius, unit: .nauticalMiles)
  }

  private static func requireTurnDirection(
    _ codable: LegTypeCodable
  ) -> TurnDirection {
    guard let raw = codable.turnDirection, let direction = TurnDirection(rawValue: raw) else {
      fatalError("LegTypeCodable.\(codable.type) requires turnDirection")
    }
    return direction
  }
}
