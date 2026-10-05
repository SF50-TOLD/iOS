/// A regular language over bytes, built from parts, that a ``ByteAutomaton`` recognizes.
///
/// It's how the grammar of the model's output is written: small enough to read, and compiled to an
/// automaton that decides, byte by byte, whether text can still grow into a whole match.
@_spi(NOTAMModelRuntime)
public indirect enum BytePattern: Sendable {
  /// Any one byte in the set.
  case byte(ByteSet)
  /// Each pattern in turn.
  case sequence([Self])
  /// Any one of the patterns.
  case either([Self])
  /// The pattern between `minimum` and `maximum` times; `nil` for no upper bound.
  case repeated(Self, minimum: Int, maximum: Int?)

  /// The pattern, or nothing.
  var optional: Self { .repeated(self, minimum: 0, maximum: 1) }

  /// The bytes of `text`, in order.
  static func literal(_ text: String) -> Self { .sequence(text.utf8.map { .byte(ByteSet([$0])) }) }

  /// Any one of the literal strings.
  static func oneOf(_ texts: [String]) -> Self { .either(texts.map(literal)) }

  /// One byte in the ASCII range, inclusive.
  static func range(_ bounds: ClosedRange<Character>) -> Self {
    guard let lower = bounds.lowerBound.asciiValue, let upper = bounds.upperBound.asciiValue else {
      preconditionFailure("A byte range must be ASCII")
    }
    return .byte(ByteSet(lower...upper))
  }

  /// The pattern followed by `other`.
  static func + (lhs: Self, rhs: Self) -> Self { .sequence([lhs, rhs]) }
}

/// A set of byte values.
@_spi(NOTAMModelRuntime)
public struct ByteSet: Sendable, Hashable {
  private var words: (UInt64, UInt64, UInt64, UInt64) = (0, 0, 0, 0)

  init(_ bytes: some Sequence<UInt8>) {
    for byte in bytes { insert(byte) }
  }

  public static func == (lhs: Self, rhs: Self) -> Bool { lhs.words == rhs.words }

  func contains(_ byte: UInt8) -> Bool {
    let bit = UInt64(1) << UInt64(byte & 63)
    switch byte >> 6 {
      case 0: return words.0 & bit != 0
      case 1: return words.1 & bit != 0
      case 2: return words.2 & bit != 0
      default: return words.3 & bit != 0
    }
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(words.0)
    hasher.combine(words.1)
    hasher.combine(words.2)
    hasher.combine(words.3)
  }

  private mutating func insert(_ byte: UInt8) {
    let bit = UInt64(1) << UInt64(byte & 63)
    switch byte >> 6 {
      case 0: words.0 |= bit
      case 1: words.1 |= bit
      case 2: words.2 |= bit
      default: words.3 |= bit
    }
  }
}
