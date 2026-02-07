import Foundation

/// Codable representation of a DME-capable navigation aid for plist serialization.
///
/// ``NavaidCodable`` stores navaid data extracted from CIFP VHF navaids.
/// Each record is uniquely identified by its ``identifier`` and ``icaoRegion``.
public struct NavaidCodable: Codable, Sendable {
  /// Short identifier (e.g., "OAK", "SFO")
  public let identifier: String

  /// ICAO region code (e.g., "K2")
  public let icaoRegion: String

  /// Facility type description (e.g., "VOR/DME", "VORTAC", "DME", "TACAN")
  public let type: String

  /// DME transponder latitude in decimal degrees
  public let latitude: Double

  /// DME transponder longitude in decimal degrees
  public let longitude: Double

  /// DME antenna elevation in feet (nil if not available)
  public let elevationFt: Double?

  public init(
    identifier: String,
    icaoRegion: String,
    type: String,
    latitude: Double,
    longitude: Double,
    elevationFt: Double?
  ) {
    self.identifier = identifier
    self.icaoRegion = icaoRegion
    self.type = type
    self.latitude = latitude
    self.longitude = longitude
    self.elevationFt = elevationFt
  }
}
