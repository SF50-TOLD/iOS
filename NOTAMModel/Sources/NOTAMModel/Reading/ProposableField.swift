// Each case name is the field's name in the model's manifest.
// swiftlint:disable raw_value_for_camel_cased_codable_enum

/// A field of a ``NOTAMExtraction`` the app may propose to the pilot.
///
/// The on-device model's manifest lists the fields that cleared its held-out gate; the app proposes
/// a model-read field only when it's listed. The formatted-report parsers read whole reports
/// deterministically, so what they read is always proposable. Obstacle distance, reference and
/// direction are never proposed, so they have no case.
public enum ProposableField: String, CaseIterable, Sendable, Codable {
  /// Which operations the runway is closed to.
  case closure
  /// How much of the runway is closed in part.
  case closedLength
  /// Which end a runway's closed portion is at.
  case closedEnd
  /// How far the threshold is displaced.
  case thresholdDisplacement
  /// Take-off run available.
  case TORA
  /// Landing distance available.
  case LDA
  /// Runway condition codes.
  case rwyCC
  /// Contaminants and their depths.
  case contaminants
  /// An obstacle's height.
  case obstacleHeight
}
// swiftlint:enable raw_value_for_camel_cased_codable_enum
