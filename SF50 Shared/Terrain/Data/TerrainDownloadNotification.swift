import Foundation

/// Names the Darwin notification the Background Assets extension and the app agree on.
///
/// The extension runs in its own process, so a stored payload reaches the app only as a
/// notification. Naming it in one place keeps the two sides from drifting apart silently.
public enum TerrainDownloadNotification {

  // MARK: - Type Properties

  /// Posted once the extension has stored a finished payload in the shared container.
  public static let completed = "codes.tim.SF50-TOLD.terrainDownloadCompleted"
}
