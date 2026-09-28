import SF50_Shared

extension NOTAMProposer {
  /// The proposer the takeoff and landing screens share, reading with the on-device model once it's
  /// installed, so a NOTAM read for one isn't read again for the other.
  static let app = NOTAMProposer { await NOTAMModelLoader.shared.reader() }
}
