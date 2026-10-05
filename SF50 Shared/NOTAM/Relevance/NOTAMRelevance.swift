import Foundation

/**
 A classifier for whether a NOTAM likely affects runway performance, for ordering the NOTAM list.

 The classifier is a logistic regression over hashed word, word-pair, word-triple and character
 4-gram features of a NOTAM's text. Its weights ship in the framework's `Data` folder and are
 loaded the first time ``shared`` is read, so read it off the main actor, as ``classifying(_:)``
 does.

 It is trained for recall: a NOTAM it misses still appears in the list, only lower.
 */
public struct NOTAMRelevance: Sendable {

  // MARK: - Type Properties

  /// The classifier whose weights ship with the app.
  public static let shared = Self(bundle: .sharedFramework)

  private static let manifestName = "notam-relevance",
    resourceDirectory = "Data",
    supportedHash = "fnv1a64",
    sigmoidInputLimit = 30.0

  // MARK: - Instance Properties

  private let weights: [Float]
  private let bias: Double

  /// The probability at or above which a NOTAM counts as relevant.
  private let threshold: Double

  // MARK: - Initializers

  private init(bundle: Bundle) {
    let manifest = Self.loadManifest(from: bundle)
    precondition(
      manifest.hash == Self.supportedHash,
      "notam-relevance.json names hash “\(manifest.hash)”, not \(Self.supportedHash)"
    )
    weights = Self.loadWeights(named: manifest.weights, count: manifest.dimension, from: bundle)
    bias = manifest.bias
    threshold = manifest.threshold
  }

  // MARK: - Type Methods

  /// Returns `notams` with each one's ``NOTAMResponse/isRelevant`` set, classifying them away from
  /// the caller's actor.
  @concurrent
  public static func classifying(_ notams: [NOTAMResponse]) async -> [NOTAMResponse] {
    notams.map(\.classifiedForRelevance)
  }

  private static func loadManifest(from bundle: Bundle) -> Manifest {
    guard
      let url = bundle.url(
        forResource: manifestName,
        withExtension: "json",
        subdirectory: resourceDirectory
      )
    else { fatalError("Could not find \(manifestName).json") }
    do {
      return try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: url))
    } catch {
      fatalError("Could not load \(manifestName).json: \(error)")
    }
  }

  /// Reads `count` little-endian `Float32`s from the resource named `name`.
  private static func loadWeights(named name: String, count: Int, from bundle: Bundle) -> [Float] {
    guard
      let url = bundle.url(forResource: name, withExtension: nil, subdirectory: resourceDirectory)
    else { fatalError("Could not find \(name)") }
    let data: Data
    do {
      data = try Data(contentsOf: url)
    } catch {
      fatalError("Could not load \(name): \(error)")
    }
    let stride = MemoryLayout<UInt32>.size
    precondition(
      data.count == count * stride,
      "\(name) holds \(data.count) bytes, not \(count * stride)"
    )
    return unsafe data.withUnsafeBytes { bytes in
      (0..<count).map { index in
        Float(
          bitPattern: UInt32(
            littleEndian: unsafe bytes.loadUnaligned(
              fromByteOffset: index * stride,
              as: UInt32.self
            )
          )
        )
      }
    }
  }

  private static func sigmoid(_ input: Double) -> Double {
    1 / (1 + exp(-min(max(input, -sigmoidInputLimit), sigmoidInputLimit)))
  }

  // MARK: - Instance Methods

  /// Whether a NOTAM likely affects runway performance.
  ///
  /// - Parameter notamText: The NOTAM's text (its E field), without its location.
  public func isRelevant(_ notamText: String) -> Bool {
    probability(notamText) >= threshold
  }

  /// The probability that a NOTAM affects runway performance.
  ///
  /// - Parameter notamText: The NOTAM's text (its E field), without its location.
  public func probability(_ notamText: String) -> Double {
    let features = NOTAMRelevanceFeatures.vector(of: notamText, dimension: weights.count),
      score = features.reduce(bias) { score, feature in
        score + Double(weights[feature.key]) * feature.value
      }
    return Self.sigmoid(score)
  }

  // MARK: - Subtypes

  /// The JSON file describing the shipped weights.
  private struct Manifest: Decodable {
    let dimension: Int
    let bias: Double
    let threshold: Double
    let weights: String
    let hash: String
  }
}

extension NOTAMResponse {
  /// This NOTAM, with ``isRelevant`` set by ``NOTAMRelevance/shared``.
  var classifiedForRelevance: Self {
    var notam = self
    notam.isRelevant = NOTAMRelevance.shared.isRelevant(notamText)
    return notam
  }
}
