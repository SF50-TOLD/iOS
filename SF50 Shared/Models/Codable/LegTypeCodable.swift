import Foundation

/**
 * Codable representation of a leg type for plist serialization.
 *
 * Stores raw `Double` values (degrees for angles, nautical miles for distances)
 * rather than `Measurement` types for stable Codable output.
 *
 * Example plist representations:
 * - `{type: "holdManual", course: 297, turnDirection: "right"}`
 * - `{type: "trackToFix", course: 135}`
 * - `{type: "radiusToFix", arcRadius: 5.2, course: 135}`
 * - `{type: "initialFix"}`
 */
public struct LegTypeCodable: Codable, Sendable {
  /// Discriminator string matching a ``LegType`` case name.
  public let type: LegTypeDiscriminator

  /// Magnetic course or heading in degrees (nil for fix-only types).
  public let course: Double?

  /// Turn direction for holds and procedure turns.
  public let turnDirection: String?

  /// Arc radius in nautical miles (nil for non-arc types).
  public let arcRadius: Double?

  public init(
    type: LegTypeDiscriminator,
    course: Double? = nil,
    turnDirection: String? = nil,
    arcRadius: Double? = nil
  ) {
    self.type = type
    self.course = course
    self.turnDirection = turnDirection
    self.arcRadius = arcRadius
  }

  // swiftlint:disable redundant_string_enum_value
  /// Discriminator values matching ``LegType`` case names.
  public enum LegTypeDiscriminator: String, Codable, Sendable {
    case initialFix = "initialFix"
    case trackToFix = "trackToFix"
    case courseToFix = "courseToFix"
    case directToFix = "directToFix"
    case radiusToFix = "radiusToFix"
    case arcToFix = "arcToFix"
    case holdToFix = "holdToFix"
    case holdToAltitude = "holdToAltitude"
    case holdManual = "holdManual"
    case fixToAltitude = "fixToAltitude"
    case trackFromFixDistance = "trackFromFixDistance"
    case trackFromFixDME = "trackFromFixDME"
    case courseToAltitude = "courseToAltitude"
    case courseToDME = "courseToDME"
    case courseToIntercept = "courseToIntercept"
    case courseToRadial = "courseToRadial"
    case headingToAltitude = "headingToAltitude"
    case headingToDME = "headingToDME"
    case headingToIntercept = "headingToIntercept"
    case headingToRadial = "headingToRadial"
    case procedureTurn = "procedureTurn"
  }
  // swiftlint:enable redundant_string_enum_value
}
