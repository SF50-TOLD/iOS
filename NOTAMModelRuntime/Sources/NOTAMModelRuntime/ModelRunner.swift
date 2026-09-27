#if canImport(CoreAI)
  internal import CoreAI
#endif
internal import Foundation

#if canImport(CoreAI)
  /// Runs a causal language model exported by Model Training's `conversion/` for one token sequence at
  /// a time, keeping its key-value cache between calls.
  ///
  /// The model has one function, `main(input_ids: [1, T] int32, positions: [T] int32) -> logits
  /// [1, vocabulary]`, and two states, `k_cache` and `v_cache`, that the caller owns and passes on every
  /// call. The same function serves prefill (T = prompt length) and decode (T = 1). Stale cache entries
  /// from an earlier NOTAM are harmless: a query sees only slots at or before its own position, and
  /// those are written first.
  ///
  /// The cache is reused between calls, so a runner is confined to one reader.
  final class ModelRunner {
    private let function: InferenceFunction
    private var keys: NDArray, values: NDArray

    /// Loads and specializes the model for the GPU, compiling once for any prompt length.
    init(contentsOf url: URL) async throws(ModelFailure) {
      var options = SpecializationOptions(preferredComputeUnitKind: .gpu)
      options.expectFrequentReshapes = true
      do {
        let model = try await AIModel(contentsOf: url, options: options)
        guard let function = try model.loadFunction(named: "main"),
          case .ndArray(let cache) = function.descriptor.stateDescriptor(of: "k_cache")
        else { throw ModelFailure.incompatibleModel }
        self.function = function
        keys = Self.zeros(cache.shape)
        values = Self.zeros(cache.shape)
      } catch let failure as ModelFailure {
        throw failure
      } catch {
        throw .loadFailed
      }
    }

    private static func run(
      _ function: InferenceFunction,
      inputs: [String: NDArray],
      keys: inout NDArray,
      values: inout NDArray
    ) async throws(ModelFailure) -> NDArray {
      var states = InferenceFunction.MutableViews()
      states.insert(&keys, for: "k_cache")
      states.insert(&values, for: "v_cache")
      do {
        var outputs = try await function.run(inputs: inputs, states: states)
        guard let logits = outputs.remove("logits")?.ndArray else {
          throw ModelFailure.incompatibleModel
        }
        return logits
      } catch let failure as ModelFailure {
        throw failure
      } catch {
        throw .inferenceFailed
      }
    }

    private static func argmax(_ logits: NDArray, among candidates: [Int]) throws(ModelFailure)
      -> Int
    {
      switch logits.scalarType {
        case .float16:
          guard let span = logits.view(as: Float16.self).contiguousElements else {
            throw .incompatibleModel
          }
          return try argmax(candidates, count: span.count) { Float(span[$0]) }
        case .float32:
          guard let span = logits.view(as: Float.self).contiguousElements else {
            throw .incompatibleModel
          }
          return try argmax(candidates, count: span.count) { span[$0] }
        default:
          throw .incompatibleModel
      }
    }

    private static func argmax(_ candidates: [Int], count: Int, logit: (Int) -> Float)
      throws(ModelFailure)
      -> Int
    {
      var best: (token: Int, logit: Float)?
      for token in candidates where token < count {
        let value = logit(token)
        if best.map({ value > $0.logit }) ?? true { best = (token, value) }
      }
      guard let best else { throw .incompatibleModel }
      return best.token
    }

    /// A zero-filled half-precision array, so no cache slot ever holds NaN bits.
    private static func zeros(_ shape: [Int]) -> NDArray {
      var array = NDArray(shape: shape, scalarType: .float16)
      let byteCount = shape.reduce(MemoryLayout<Float16>.size, *)
      _ = array.mutableRawView().withUnsafeMutableBytes { pointer, _, _ in
        unsafe memset(pointer, 0, byteCount)
      }
      return array
    }

    /// Of `candidates`, the token the model finds most likely after `tokens`, which start at `position`.
    func mostLikely(of candidates: [Int], after tokens: [Int32], at position: Int)
      async throws(ModelFailure) -> Int
    {
      let positions = (0..<tokens.count).map { Int32(position + $0) }
      let inputs = [
        "input_ids": NDArray(scalars: tokens, shape: [1, tokens.count]),
        "positions": NDArray(scalars: positions, shape: [positions.count])
      ]
      let logits = try await Self.run(function, inputs: inputs, keys: &keys, values: &values)
      return try Self.argmax(logits, among: candidates)
    }
  }

#else
  // The stand-in mirrors the Core AI runner's interface, which is asynchronous.
  // swiftlint:disable async_without_await
  /// Core AI isn't available on this platform (the iOS Simulator), so no model loads.
  final class ModelRunner {
    init(contentsOf _: URL) async throws(ModelFailure) { throw .loadFailed }

    func mostLikely(of _: [Int], after _: [Int32], at _: Int) async throws(ModelFailure) -> Int {
      throw .inferenceFailed
    }
  }
// swiftlint:enable async_without_await
#endif

/// Why the on-device model couldn't run.
enum ModelFailure: Error, Sendable {
  /// The model files couldn't be loaded or specialized.
  case loadFailed
  // periphery:ignore - thrown only by the device runner, which the Simulator build Periphery scans leaves out
  /// The model doesn't have the function, states or outputs the reader expects.
  case incompatibleModel
  /// A model call failed.
  case inferenceFailed
}
