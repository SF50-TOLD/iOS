public import Foundation
public import NOTAMModel
internal import Tokenizers

/**
 Reads a NOTAM with the fine-tuned on-device model.

 The model writes ``ReadingFormat`` text one token at a time, greedily, and a ``GrammarConstraint``
 allows only tokens that keep the text in the format — so the output always parses, and a field can
 only hold a value in the schema's range. A NOTAM always reads the same way.

 The model folder holds `notam-model.json` (``Manifest``), the Core AI model it names, and the
 tokenizer files (`tokenizer.json`, `tokenizer_config.json`).
 */
public actor NOTAMModelReader: NOTAMReader {
  private static let manifestName = "notam-model.json"

  private let manifest: Manifest
  private let tokenizer: any Tokenizer
  private let runner: ModelRunner
  private let constraint: GrammarConstraint

  /// Loads the model, its tokenizer and the output grammar.
  ///
  /// - Parameter folder: The model folder.
  /// - Throws: ``LoadFailure`` when a file is missing or the model can't be specialized.
  public init(folder: URL) async throws(LoadFailure) {
    let manifest: Manifest
    do {
      manifest = try JSONDecoder().decode(
        Manifest.self,
        from: Data(contentsOf: folder.appending(path: Self.manifestName))
      )
    } catch {
      throw .missingManifest
    }
    guard manifest.schemaVersion == NOTAMExtraction.schemaVersion else {
      throw .schemaMismatch(model: manifest.schemaVersion)
    }
    let tokenizer: any Tokenizer
    do {
      tokenizer = try await AutoTokenizer.from(modelFolder: folder)
    } catch {
      throw .missingTokenizer
    }
    do {
      runner = try await ModelRunner(contentsOf: folder.appending(path: manifest.model))
    } catch {
      throw .modelUnloadable
    }
    self.manifest = manifest
    self.tokenizer = tokenizer
    constraint = GrammarConstraint(
      pattern: ReadingGrammar.pattern,
      vocabulary: ByteLevelVocabulary.bytes(of: tokenizer, count: manifest.vocabularySize),
      endOfSequence: manifest.endOfSequence
    )
  }

  /// Reads the runway-performance facts one NOTAM states.
  ///
  /// - Parameters:
  ///   - notamText: The NOTAM text as the NOTAM API returns it.
  ///   - location: The NOTAM's ICAO location.
  /// - Throws: ``NOTAMReadFailure`` when the NOTAM is too long, the model's reading doesn't hold together,
  ///   the model fails, or the task is cancelled.
  public func read(notamText: String, location: String) async throws(NOTAMReadFailure)
    -> NOTAMExtraction
  {
    let prompt = manifest.promptTemplate.replacing(
      "{prompt}",
      with: "Location: \(location)\n\n\(notamText)"
    )
    let promptTokens = tokenizer.encode(text: prompt, addSpecialTokens: false).map(Int32.init)
    guard promptTokens.count + manifest.maximumOutputTokens <= manifest.contextLength else {
      throw .tooLong
    }
    let outputTokens = try await generate(after: promptTokens)
    guard
      let text = String(bytes: outputTokens.flatMap { constraint.bytes(of: $0) }, encoding: .utf8)
    else { throw .malformed }
    do {
      return try Self.validated(ReadingFormat.decode(text), notamText: notamText)
    } catch {
      throw .malformed
    }
  }

  private func generate(after promptTokens: [Int32]) async throws(NOTAMReadFailure) -> [Int] {
    var state = constraint.start, output: [Int] = []
    var next = promptTokens, position = 0
    while output.count < manifest.maximumOutputTokens {
      guard !Task.isCancelled else { throw .cancelled }
      let candidates = constraint.allowedTokens(in: state)
      let token: Int
      do {
        token = try await runner.mostLikely(of: candidates, after: next, at: position)
      } catch {
        throw .modelFailed
      }
      if token == manifest.endOfSequence { return output }
      guard let advanced = constraint.advance(state, by: token) else { throw .malformed }
      state = advanced
      output.append(token)
      position += next.count
      next = [Int32(token)]
    }
    throw .malformed
  }
}

extension NOTAMModelReader {
  /// The extraction, if every effect states something, declared distances state at least one, and
  /// every number it holds is one the NOTAM states (``ReadingGrounding``).
  fileprivate static func validated(_ extraction: NOTAMExtraction, notamText: String)
    throws(NOTAMReadFailure) -> NOTAMExtraction
  {
    for effect in extraction.effects {
      let statesSomething =
        effect.closure != .none || effect.closedLength != nil || effect.closedEnd != nil
        || effect.thresholdDisplacement != nil || effect.declaredDistances != nil
        || effect.surfaceCondition != nil || effect.obstacle != nil
      let distances = effect.declaredDistances.map { [$0.TORA, $0.TODA, $0.ASDA, $0.LDA] }
      guard statesSomething, distances?.contains(where: { $0 != nil }) ?? true else {
        throw .malformed
      }
    }
    guard ReadingGrounding.isGrounded(extraction, in: notamText.uppercased()) else {
      throw .malformed
    }
    return extraction
  }

  /// The model folder's `notam-model.json`, written by Model Training's `conversion/`.
  struct Manifest: Decodable {
    /// The Core AI model's file name within the folder.
    let model: String
    /// The Model Training schema version the model was trained on.
    let schemaVersion: String
    /// The prompt, with `{prompt}` where `Location: <location>`, a blank line and the NOTAM go.
    let promptTemplate: String
    /// The token that ends the model's reading.
    let endOfSequence: Int
    /// The number of logits the model produces.
    let vocabularySize: Int
    /// The most tokens the model's cache holds, prompt and reading together.
    let contextLength: Int
    /// The longest reading the model may write.
    let maximumOutputTokens: Int
  }

  /// Why the on-device model couldn't be loaded.
  public enum LoadFailure: Error, Sendable, Equatable {
    /// The folder has no readable `notam-model.json`.
    case missingManifest
    /// The model was trained on a different schema version than this build reads.
    case schemaMismatch(model: String)
    /// The folder has no readable tokenizer.
    case missingTokenizer
    /// The Core AI model couldn't be loaded or specialized.
    case modelUnloadable
  }
}
