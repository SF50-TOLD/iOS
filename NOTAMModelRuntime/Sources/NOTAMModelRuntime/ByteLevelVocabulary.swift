internal import Tokenizers

/// Each token's bytes, for a byte-level BPE tokenizer (GPT-2, Qwen).
///
/// A byte-level BPE vocabulary spells every byte with a printable stand-in character; mapping the
/// stand-ins back gives the bytes a token adds to the output, which is what the grammar constrains.
/// Special tokens, and any token that isn't spelled in stand-ins, have no bytes.
enum ByteLevelVocabulary {
  /// The byte each stand-in character represents.
  private static let bytesByStandIn: [Character: UInt8] = {
    let printable = Array(0x21...0x7E) + Array(0xA1...0xAC) + Array(0xAE...0xFF)
    var standIns: [Character: UInt8] = [:]
    for byte in printable { standIns[Character(UnicodeScalar(UInt8(byte)))] = UInt8(byte) }
    var next = 0
    for byte in 0...255 where !printable.contains(byte) {
      guard let scalar = UnicodeScalar(256 + next) else {
        preconditionFailure("A stand-in is a scalar")
      }
      standIns[Character(scalar)] = UInt8(byte)
      next += 1
    }
    return standIns
  }()

  /// Every token's bytes, indexed by token ID.
  static func bytes(of tokenizer: any Tokenizer, count: Int) -> [[UInt8]] {
    (0..<count).map { id in
      guard let token = tokenizer.convertIdToToken(id), !isSpecial(token) else { return [] }
      let bytes = token.compactMap { bytesByStandIn[$0] }
      return bytes.count == token.count ? bytes : []
    }
  }

  private static func isSpecial(_ token: String) -> Bool {
    token.hasPrefix("<|") && token.hasSuffix("|>")
  }
}
