/**
 Which tokens the model may emit next so that its output stays in a grammar.

 The vocabulary is a trie of each token's bytes. For a grammar state, walking the trie alongside the
 ``ByteAutomaton`` finds every token whose bytes keep a match possible, pruning a whole subtree at the
 first byte that can't follow. The answer depends only on the automaton state, so it's computed once
 per state and reused: after the first few NOTAMs, masking costs a lookup.

 The end-of-sequence token is allowed exactly where the text so far is a whole match.

 It caches as it goes, so it's confined to one decoding task.
 */
@_spi(NOTAMModelRuntime)
public final class GrammarConstraint {
  private let automaton: ByteAutomaton
  private let trie: TokenTrie
  private let endOfSequence: Int
  private var allowedByState: [Int: [Int]] = [:]

  /// The automaton state before the model's first token.
  public var start: Int { automaton.start }

  /// - Parameters:
  ///   - pattern: The grammar the output must match.
  ///   - vocabulary: Each token's bytes, indexed by token ID. Tokens with no bytes (special tokens)
  ///     are never allowed.
  ///   - endOfSequence: The token that ends the output.
  public init(pattern: BytePattern, vocabulary: [[UInt8]], endOfSequence: Int) {
    automaton = ByteAutomaton(pattern)
    trie = TokenTrie(vocabulary)
    self.endOfSequence = endOfSequence
  }

  /// Every token that may follow in `state`, including end-of-sequence where the output may end.
  public func allowedTokens(in state: Int) -> [Int] {
    if let known = allowedByState[state] { return known }
    var allowed: [Int] = []
    collect(node: trie.root, state: state, into: &allowed)
    if automaton.isAccepting(state) { allowed.append(endOfSequence) }
    allowedByState[state] = allowed
    return allowed
  }

  /// The state after `token`, or `nil` if `token` isn't allowed in `state`.
  public func advance(_ state: Int, by token: Int) -> Int? {
    guard token != endOfSequence else { return nil }
    return trie.bytes(of: token).flatMap { automaton.step(state, $0) }
  }

  /// The bytes `token` adds to the output; none for a special token.
  public func bytes(of token: Int) -> [UInt8] { trie.bytes(of: token) ?? [] }

  private func collect(node: Int, state: Int, into allowed: inout [Int]) {
    for (byte, child) in trie.children(of: node) {
      guard let next = automaton.step(state, byte) else { continue }
      allowed += trie.tokens(endingAt: child)
      collect(node: child, state: next, into: &allowed)
    }
  }
}

/// Token byte strings, shared by prefix.
private struct TokenTrie {
  let root = 0
  private var children: [[(UInt8, Int)]] = [[]]
  private var tokensEnding: [[Int]] = [[]]
  private let vocabulary: [[UInt8]]

  init(_ vocabulary: [[UInt8]]) {
    self.vocabulary = vocabulary
    for (token, bytes) in vocabulary.enumerated() where !bytes.isEmpty { insert(token, bytes) }
  }

  func children(of node: Int) -> [(UInt8, Int)] { children[node] }
  func tokens(endingAt node: Int) -> [Int] { tokensEnding[node] }
  func bytes(of token: Int) -> [UInt8]? {
    vocabulary.indices.contains(token) && !vocabulary[token].isEmpty ? vocabulary[token] : nil
  }

  private mutating func insert(_ token: Int, _ bytes: [UInt8]) {
    var node = root
    for byte in bytes {
      if let child = children[node].first(where: { $0.0 == byte })?.1 {
        node = child
      } else {
        children.append([])
        tokensEnding.append([])
        children[node].append((byte, children.count - 1))
        node = children.count - 1
      }
    }
    tokensEnding[node].append(token)
  }
}
