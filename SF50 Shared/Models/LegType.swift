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
    guard let raw = codable.turnDirection, let dir = TurnDirection(rawValue: raw) else {
      fatalError("LegTypeCodable.\(codable.type) requires turnDirection")
    }
    return dir
  }
}
