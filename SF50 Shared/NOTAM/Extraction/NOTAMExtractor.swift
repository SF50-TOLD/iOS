public import NOTAMModel

/// Reads raw NOTAM text into a proposed `NOTAMExtraction`.
///
/// A NOTAM in a fixed report format (FICON, RSC, SNOWTAM, FAA obstacle) is read exactly by
/// `FormattedReportParser`; any other NOTAM goes to the fine-tuned on-device model, when it's
/// installed.
///
/// The extraction is a *proposal* for the pilot to confirm, never a value a calculation uses directly.
/// Every model failure surfaces as ``Failure`` — a NOTAM the extractor couldn't read, never a guess.
/// The model decodes greedily, so a NOTAM always reads the same way.
public struct NOTAMExtractor: Sendable {
  private let reader: (any NOTAMReader)?

  /// Creates an extractor.
  ///
  /// - Parameter reader: The on-device model (`NOTAMModelRuntime`'s `NOTAMModelReader`), or `nil` when
  ///   it isn't installed; formatted reports are read either way.
  public init(reader: (any NOTAMReader)?) {
    self.reader = reader
  }

  /// Reads one NOTAM, and says which of its fields may be proposed to the pilot.
  ///
  /// - Parameters:
  ///   - notamText: The NOTAM text as the NOTAM API returns it.
  ///   - location: The NOTAM's ICAO location.
  /// - Throws: ``Failure`` when the model is unavailable or couldn't read the NOTAM.
  public func read(notamText: String, location: String) async throws(Failure) -> Reading {
    if let extraction = FormattedReportParser.parse(notamText: notamText) {
      return Reading(extraction: extraction, source: .parser)
    }
    guard let reader else { throw .modelUnavailable }
    do {
      let extraction = try await reader.read(notamText: notamText, location: location)
      return Reading(extraction: extraction, source: .model(version: reader.modelVersion))
        .limited(to: reader.proposableFields)
    } catch .cancelled {
      throw .cancelled
    } catch {
      throw .unreadable(Reason(error))
    }
  }
}

extension NOTAMExtractor {
  /// One NOTAM's reading, and which of its fields may be proposed.
  public struct Reading: Sendable, Equatable {

    // MARK: - Instance Properties

    /// What the NOTAM states.
    public let extraction: NOTAMExtraction

    /// What read it.
    public let source: Source

    /// The fields whose values may be proposed to the pilot: every field of a formatted report,
    /// and of a model reading only those the model cleared its gate on.
    public private(set) var proposableFields = Set(ProposableField.allCases)

    // MARK: - Initializers

    /// Creates a reading whose every field may be proposed.
    public init(extraction: NOTAMExtraction, source: Source) {
      self.extraction = extraction
      self.source = source
    }

    // MARK: - Instance Methods

    /// This reading, with only `fields` proposable.
    public func limited(to fields: Set<ProposableField>) -> Self {
      var reading = self
      reading.proposableFields = fields
      return reading
    }
  }

  /// What read a NOTAM.
  public enum Source: Sendable, Equatable, Hashable {
    /// A deterministic parser for a formatted report (FICON, RSC, SNOWTAM, FAA obstacle).
    case parser
    /// The on-device model, of the given version.
    case model(version: String)
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

    // periphery:ignore - read only by the NOTAMExtractionEvaluation harness, which Periphery doesn't scan
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
