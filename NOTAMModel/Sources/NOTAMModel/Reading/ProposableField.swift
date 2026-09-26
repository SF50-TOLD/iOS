// Each case name is the field's name in the model's manifest.
// swiftlint:disable raw_value_for_camel_cased_codable_enum

/// A field of a ``NOTAMExtraction`` the app may propose to the pilot.
///
/// The on-device model's manifest lists the fields that cleared its held-out gate; the app proposes
/// a model-read field only when it's listed. The formatted-report parsers read whole reports
/// deterministically, so what they read is always proposable. Obstacle distance, reference, bearing
/// and position are never proposed, so they have no case.
public enum ProposableField: String, CaseIterable, Sendable, Codable {
  /// Whether the runway is closed, fully or in part.
  case closure
  /// How much of the runway is closed.
  case closedLength
  /// Which end of the runway is closed.
  case closedEnd
  /// How far the threshold is displaced.
  case thresholdDisplacement
  /// Take-off run available.
  case TORA
  /// Take-off distance available.
  case TODA
  /// Accelerate-stop distance available.
  case ASDA
  /// Landing distance available.
  case LDA
  /// Runway condition codes.
  case rwyCC
  /// Contaminants and their depths.
  case contaminants
  /// An obstacle's height above ground.
  case obstacleHeightAGL
  /// An obstacle's height above mean sea level.
  case obstacleHeightMSL
}
// swiftlint:enable raw_value_for_camel_cased_codable_enum
