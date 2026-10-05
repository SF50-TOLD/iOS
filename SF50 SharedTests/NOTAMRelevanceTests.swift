import Foundation
import Testing

@testable import SF50_Shared

struct `NOTAM relevance classifier` {
  private static let tolerance = 1e-5

  /// Each line of the parity file the training run exported: a NOTAM's text and the probability the
  /// shipped weights give it there.
  private static func parityCases() throws -> [ParityCase] {
    let url = try #require(
      Bundle(for: BundleAnchor.self).url(
        forResource: "notam-relevance-parity",
        withExtension: "jsonl"
      )
    )
    return try String(contentsOf: url, encoding: .utf8)
      .split(whereSeparator: \.isNewline)
      .map { try JSONDecoder().decode(ParityCase.self, from: Data($0.utf8)) }
  }

  @Test
  func `scores every parity NOTAM as the training code does`() throws {
    let cases = try Self.parityCases()
    #expect(!cases.isEmpty)
    for parityCase in cases {
      let probability = NOTAMRelevance.shared.probability(parityCase.text)
      #expect(
        abs(probability - parityCase.probability) <= Self.tolerance,
        "\(parityCase.text.debugDescription): \(probability), not \(parityCase.probability)"
      )
    }
  }

  private struct ParityCase: Decodable {
    let text: String
    let probability: Double
  }
}

/// Resolves this test bundle, which holds the parity file.
private final class BundleAnchor {}
