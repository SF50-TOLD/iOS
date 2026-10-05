public import FoundationModels

/// Reads a NOTAM with one of Apple's stock language models — the on-device `SystemLanguageModel`
/// or `PrivateCloudComputeLanguageModel` — generating a ``NOTAMExtraction`` directly.
///
/// The extraction's `@Guide` descriptions reach the model as the response schema, and
/// ``StockModelInstructions`` carry the rules that span fields. Each read uses a fresh session with
/// greedy sampling, so a NOTAM always reads the same way and one NOTAM can't colour the next. No
/// stock model has cleared the Auto-Fill gate, so a reading proposes nothing until one does.
public struct StockModelReader: NOTAMReader {
  private static let options = GenerationOptions(samplingMode: .greedy)

  nonisolated public let modelVersion: String
  nonisolated public let proposableFields: Set<ProposableField> = []

  private let session: @Sendable () -> LanguageModelSession

  /// Creates a reader using `model`.
  ///
  /// - Parameters:
  ///   - model: The stock model.
  ///   - name: Identifies the model in the readings it makes.
  public init(model: some LanguageModel, name: String) {
    modelVersion = name
    session = { LanguageModelSession(model: model, instructions: StockModelInstructions.text) }
  }

  /// Reads one NOTAM.
  ///
  /// - Throws: ``NOTAMReadFailure`` when the NOTAM is too long, the model declines it or can't
  ///   finish a reading of it, or the model fails to run. An error the framework doesn't classify,
  ///   such as a reading that doesn't decode, is a reading that didn't hold together.
  public func read(notamText: String, location: String) async throws(NOTAMReadFailure)
    -> NOTAMExtraction
  {
    do {
      return try await session().respond(
        to: Prompt("Location: \(location)\n\n\(notamText)"),
        generating: NOTAMExtraction.self,
        options: Self.options
      ).content
    } catch let error as LanguageModelError {
      throw NOTAMReadFailure(error)
    } catch is CancellationError {
      throw .cancelled
    } catch is SystemLanguageModel.Error, is PrivateCloudComputeLanguageModel.Error {
      throw .modelFailed
    } catch {
      throw .malformed
    }
  }
}

extension NOTAMReadFailure {
  fileprivate init(_ error: LanguageModelError) {
    switch error {
      case .contextSizeExceeded: self = .tooLong
      case .guardrailViolation, .refusal, .unsupportedLanguageOrLocale: self = .declined
      case .timeout: self = .malformed
      case .rateLimited, .unsupportedCapability, .unsupportedGenerationGuide,
        .unsupportedTranscriptContent:
        self = .modelFailed
      @unknown default: self = .modelFailed
    }
  }
}
