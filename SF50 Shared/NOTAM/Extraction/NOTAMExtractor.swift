public import FoundationModels

/// Reads raw NOTAM text into a proposed ``NOTAMExtraction`` using the on-device language model.
///
/// The extraction is a *proposal* for the pilot to confirm, never a value a calculation uses directly.
/// Every model failure surfaces as ``Failure/unreadable(_:)`` — a NOTAM the extractor couldn't read,
/// never a guess. Each call uses a fresh session with greedy sampling, so a NOTAM always reads the same
/// way and one NOTAM can't colour the next.
public struct NOTAMExtractor: Sendable {
  private static let options = GenerationOptions(samplingMode: .greedy)

  private let model: SystemLanguageModel

  /// Whether the on-device model can run on this device right now.
  public var isAvailable: Bool { model.isAvailable }

  /// Creates an extractor using the given on-device model.
  public init(model: SystemLanguageModel = .init(useCase: .general)) {
    self.model = model
  }

  /// Proposes the runway-performance facts one NOTAM states.
  ///
  /// - Parameters:
  ///   - notamText: The NOTAM text as the NOTAM API returns it.
  ///   - location: The NOTAM's ICAO location.
  /// - Throws: ``Failure`` when the model is unavailable or couldn't read the NOTAM.
  public func extract(notamText: String, location: String) async throws(Failure) -> NOTAMExtraction
  {
    try await extract(prompt: Prompt("Location: \(location)\n\n\(notamText)"))
  }

  func extract(prompt: Prompt) async throws(Failure) -> NOTAMExtraction {
    guard isAvailable else { throw .modelUnavailable }
    let session = LanguageModelSession(model: model, instructions: NOTAMExtractionInstructions.text)
    do {
      return try await session.respond(
        to: prompt,
        generating: NOTAMExtraction.self,
        options: Self.options
      ).content
    } catch let error as LanguageModelError {
      throw .unreadable(Reason(error))
    } catch is CancellationError {
      throw .cancelled
    } catch {
      throw .unreadable(.unknown)
    }
  }
}

extension NOTAMExtractor {
  /// Why a NOTAM couldn't be read.
  public enum Failure: Error, Sendable {
    /// The on-device model isn't available on this device.
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
    /// The model declined the text.
    case declined
    /// The model didn't answer in time.
    case timedOut
    /// The NOTAM is in a language or locale the model doesn't support.
    case unsupportedLanguage
    /// The model is busy with other requests.
    case busy
    /// The model can't run the extraction as the app configures it: a guide, capability or
    /// transcript it rejects. This never depends on the NOTAM, and should never happen.
    case misconfigured
    /// An error the extractor doesn't classify.
    case unknown

    /// Whether the failure comes from this NOTAM's text rather than from the model or the app.
    var concernsThisNOTAM: Bool {
      switch self {
        case .tooLong, .declined, .timedOut, .unsupportedLanguage: true
        case .busy, .misconfigured, .unknown: false
      }
    }

    init(_ error: LanguageModelError) {
      switch error {
        case .contextSizeExceeded: self = .tooLong
        case .guardrailViolation, .refusal: self = .declined
        case .timeout: self = .timedOut
        case .unsupportedLanguageOrLocale: self = .unsupportedLanguage
        case .unsupportedCapability, .unsupportedGenerationGuide, .unsupportedTranscriptContent:
          self = .misconfigured
        case .rateLimited: self = .busy
        @unknown default: self = .unknown
      }
    }
  }
}
