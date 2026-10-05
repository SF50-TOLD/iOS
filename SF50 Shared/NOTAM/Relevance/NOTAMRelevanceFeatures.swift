import Foundation

/**
 The hashed feature vector ``NOTAMRelevance`` scores a NOTAM's text by.

 This reproduces `features` in the Model Training repository's `training/relevance.py` exactly, so
 that the shipped weights score a NOTAM here as they did when trained:

 1. The text is upper-cased, every run of whitespace collapsed to one space, and every number
    replaced by `#`.
 2. The tokens are runs of `A`–`Z` and `#`, and every other non-space character on its own.
 3. Each token names a word feature; each adjacent pair and triple, a pair and triple feature; and
    each 4-character window of a token longer than 4 characters, a character feature.
 4. Each feature's index is the 64-bit FNV-1a hash of its name's UTF-8 bytes, modulo the dimension,
    and its value is `1 + ln(count)`. Features that land on the same index add up, and the vector
    is scaled to unit length.

 Everything works on Unicode scalars, as Python strings do, rather than on grapheme clusters.
 */
enum NOTAMRelevanceFeatures {
  private static let number = #/\d+(?:[.,]\d+)?/#.matchingSemantics(.unicodeScalar),
    token = #/[A-Z#]+|[^\sA-Z#]/#.matchingSemantics(.unicodeScalar),
    characterWindow = 4,
    FNVOffset: UInt64 = 0xcbf2_9ce4_8422_2325,
    FNVPrime: UInt64 = 0x100_0000_01b3

  /// Python's `str.isspace`: Unicode White_Space, plus the information separators U+001C–U+001F.
  private static let informationSeparators: ClosedRange<UInt32> = 0x1C...0x1F

  /// The unit-length feature vector of `text`, as index → value.
  static func vector(of text: String, dimension: Int) -> [Int: Double] {
    var vector: [Int: Double] = [:]
    for (hash, count) in featureCounts(of: tokens(of: text)) {
      vector[Int(hash % UInt64(dimension)), default: 0] += 1 + log(Double(count))
    }
    let norm = vector.values.reduce(0) { $0 + $1 * $1 }.squareRoot()
    guard norm > 0 else { return vector }
    return vector.mapValues { $0 / norm }
  }

  private static func tokens(of text: String) -> [String] {
    normalized(text).matches(of: token).map { String($0.output) }
  }

  /// `text` upper-cased, with its whitespace collapsed and its numbers replaced by `#`.
  private static func normalized(_ text: String) -> String {
    let words = text.uppercased().unicodeScalars.split(whereSeparator: isWhitespace),
      collapsed = words.map { String(String.UnicodeScalarView($0)) }.joined(separator: " ")
    return collapsed.replacing(number, with: "#")
  }

  private static func isWhitespace(_ scalar: Unicode.Scalar) -> Bool {
    scalar.properties.isWhitespace || informationSeparators.contains(scalar.value)
  }

  /// How often each feature name occurs among `tokens`, keyed by the name's FNV-1a hash.
  private static func featureCounts(of tokens: [String]) -> [UInt64: Int] {
    featureNames(of: tokens).reduce(into: [:]) { counts, name in
      counts[FNV1a64(name), default: 0] += 1
    }
  }

  private static func featureNames(of tokens: [String]) -> [String] {
    tokens.indices.flatMap { index in
      let token = tokens[index],
        pair = tokens.dropFirst(index).prefix(2),
        triple = tokens.dropFirst(index).prefix(3)
      return ["w:\(token)"]
        + (pair.count == 2 ? ["b:" + pair.joined(separator: "_")] : [])
        + (triple.count == 3 ? ["t:" + triple.joined(separator: "_")] : [])
        + characterWindows(of: token).map { "c:\($0)" }
    }
  }

  /// Every 4-scalar window of `token`, when it is longer than 4 scalars.
  private static func characterWindows(of token: String) -> [String] {
    let scalars = Array(token.unicodeScalars)
    guard scalars.count > characterWindow else { return [] }
    return (0...(scalars.count - characterWindow)).map { start in
      var window = String.UnicodeScalarView()
      window.append(contentsOf: scalars[start..<(start + characterWindow)])
      return String(window)
    }
  }

  /// The 64-bit FNV-1a hash of `name`'s UTF-8 bytes.
  private static func FNV1a64(_ name: String) -> UInt64 {
    name.utf8.reduce(FNVOffset) { hash, byte in (hash ^ UInt64(byte)) &* FNVPrime }
  }
}
