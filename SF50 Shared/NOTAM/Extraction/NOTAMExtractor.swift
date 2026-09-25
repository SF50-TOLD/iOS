public import NOTAMModel

/// Reads raw NOTAM text into a proposed ``NOTAMExtraction``.
///
/// A NOTAM in a fixed report format (FICON, RSC, SNOWTAM, FAA obstacle) is read exactly by
/// ``FormattedReportParser``; any other NOTAM goes to the fine-tuned on-device model, when it's
/// installed.
///
/// The extraction is a *proposal* for the pilot to confirm, never a value a calculation uses directly.
/// Every model failure surfaces as ``Failure`` — a NOTAM the extractor couldn't read, never a guess.
/// The model decodes greedily, so a NOTAM always reads the same way.
public struct NOTAMExtractor: Sendable {
  private let reader: (any NOTAMReader)?

  /// Whether NOTAMs outside the fixed report formats can be read on this device right now.
  public var isModelAvailable: Bool { reader != nil }

  /// Creates an extractor.
  ///
  /// - Parameter reader: The on-device model (`NOTAMModelRuntime`'s `NOTAMModelReader`), or `nil` when
  ///   it isn't installed; formatted reports are read either way.
  public init(reader: (any NOTAMReader)?) {
    self.reader = reader
  }

  /// Proposes the runway-performance facts one NOTAM states.
  ///
  /// - Parameters:
  ///   - notamText: The NOTAM text as the NOTAM API returns it.
  ///   - location: The NOTAM's ICAO location.
  /// - Throws: ``Failure`` when the model is unavailable or couldn't read the NOTAM.
  public func extract(notamText: String, location: String) async throws(Failure) -> NOTAMExtraction
  {
    if let reading = FormattedReportParser.parse(notamText: notamText) { return reading }
    guard let reader else { throw .modelUnavailable }
    do {
      return try await reader.read(notamText: notamText, location: location)
    } catch .cancelled {
      throw .cancelled
    } catch {
      throw .unreadable(Reason(error))
    }
  }
}

extension NOTAMExtractor {
  /// Why a NOTAM couldn't be read.
  public enum Failure: Error, Sendable {
    /// The on-device model isn't installed on this device.
    case modelUnavailable
    /// The reading was cancelled before it finished.
    case cancelled
    /// The model couldn't produce a reading of this NOTAM.
    case unreadable(Reason)
  }

  /// What stopped the model from reading a NOTAM.
  public enum Reason: Sendable {
    /// The NOTAM is too long for the model's context.
    case tooLong
    /// The model's reading didn't finish or didn't hold together.
    case unrecognized
    /// The model failed to run. This never depends on the NOTAM, and should never happen.
    case modelFailed

    /// Whether the failure comes from this NOTAM's text rather than from the model or the app.
    var concernsThisNOTAM: Bool {
      switch self {
        case .tooLong, .unrecognized: true
        case .modelFailed: false
      }
    }

    init(_ failure: NOTAMReadFailure) {
      switch failure {
        case .tooLong: self = .tooLong
        case .malformed: self = .unrecognized
        case .modelFailed, .cancelled: self = .modelFailed
      }
    }
  }
}
