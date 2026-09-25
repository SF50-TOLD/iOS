/// Something that reads the runway-performance facts a NOTAM states: the on-device model
/// (`NOTAMModelRuntime`'s `NOTAMModelReader`), or a stand-in in tests.
public protocol NOTAMReader: Sendable {
  /// Reads one NOTAM.
  ///
  /// - Parameters:
  ///   - notamText: The NOTAM text as the NOTAM API returns it.
  ///   - location: The NOTAM's ICAO location.
  /// - Throws: ``NOTAMReadFailure`` when the NOTAM can't be read.
  func read(notamText: String, location: String) async throws(NOTAMReadFailure) -> NOTAMExtraction
}

/// Why a ``NOTAMReader`` couldn't read a NOTAM.
public enum NOTAMReadFailure: Error, Sendable, Equatable {
  /// The NOTAM and the longest reading don't fit the model's context.
  case tooLong
  /// The model's reading didn't finish, or doesn't hold together.
  case malformed
  /// The model failed to run.
  case modelFailed
  /// The reading was cancelled before it finished.
  case cancelled
}
