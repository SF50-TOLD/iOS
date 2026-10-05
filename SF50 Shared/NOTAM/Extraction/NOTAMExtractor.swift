public import NOTAMModel
public import NOTAMParsing

/// Reads raw NOTAM text into a proposed `NOTAMExtraction`.
///
/// A NOTAM in a fixed report format (FICON, RSC, SNOWTAM, FAA obstacle) is read exactly by
/// `FormattedReportParser`; any other NOTAM goes to the fine-tuned on-device model, when it's
/// installed.
///
/// The extraction is a *proposal* for the pilot to confirm, never a value a calculation uses directly.
/// Every model failure surfaces as ``Failure`` — a NOTAM the extractor couldn't read, never a guess.
/// The model decodes greedily, so a NOTAM always reads the same way. The parsers' grammars are built
/// once per extractor, so read a batch of NOTAMs with one.
public struct NOTAMExtractor {
  private let reader: (any NOTAMReader)?
  private let parser: FormattedReportParser?

  /// Creates an extractor.
  ///
  /// - Parameters:
  ///   - reader: The on-device model (`NOTAMModelRuntime`'s `NOTAMModelReader`), or `nil` when it
  ///     isn't installed.
  ///   - parsesFormattedReports: Whether formatted reports are read by the parsers rather than the
  ///     model; `false` measures what the model reads of them.
  public init(reader: (any NOTAMReader)?, parsesFormattedReports: Bool = true) {
    self.reader = reader
    parser = parsesFormattedReports ? FormattedReportParser() : nil
  }

  /// Reads one NOTAM, and says which of its fields may be proposed to the pilot.
  ///
  /// - Parameters:
  ///   - notamText: The NOTAM text as the NOTAM API returns it.
  ///   - location: The NOTAM's ICAO location.
  /// - Throws: ``Failure`` when the model is unavailable or couldn't read the NOTAM.
  public func read(notamText: String, location: String) async throws(Failure) -> Reading {
    if let report = parser?.parse(notamText: notamText) {
      return Reading(extraction: NOTAMExtraction(report), source: .parser, report: report)
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

    /// The formatted report a parser read, which says more about an obstacle than an extraction
    /// can: its compass direction from the runway end; `nil` for a model reading.
    public let report: FormattedReport?

    /// The fields whose values may be proposed to the pilot: every field of a formatted report,
    /// and of a model reading only those the model cleared its gate on.
    public private(set) var proposableFields = Set(ProposableField.allCases)

    // MARK: - Initializers

    /// Creates a reading whose every field may be proposed.
    public init(extraction: NOTAMExtraction, source: Source, report: FormattedReport? = nil) {
      self.extraction = extraction
      self.source = source
      self.report = report
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
    /// The model declined to read the NOTAM.
    case declined
    /// The model failed to run. This never depends on the NOTAM, and should never happen.
    case modelFailed

    // periphery:ignore - read only by the NOTAMExtractionEvaluation harness, which Periphery doesn't scan
    /// Whether the failure comes from this NOTAM's text rather than from the model or the app.
    var concernsThisNOTAM: Bool {
      switch self {
        case .tooLong, .unrecognized, .declined: true
        case .modelFailed: false
      }
    }

    init(_ failure: NOTAMReadFailure) {
      switch failure {
        case .tooLong: self = .tooLong
        case .malformed: self = .unrecognized
        case .declined: self = .declined
        case .modelFailed, .cancelled: self = .modelFailed
      }
    }
  }
}
