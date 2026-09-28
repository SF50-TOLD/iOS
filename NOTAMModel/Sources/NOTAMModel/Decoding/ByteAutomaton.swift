/// Decides, byte by byte, whether text can still grow into a match of a ``BytePattern``.
///
/// The pattern compiles to a nondeterministic automaton (Thompson's construction); deterministic states
/// are built from it only as decoding reaches them, and each transition is computed once. A state is
/// an `Int`; ``start`` is the empty text, and ``step(_:_:)`` returns `nil` once no match is possible.
///
/// It caches as it goes, so it's confined to one decoding task.
final class ByteAutomaton {
  private static let unknown: Int32 = -2, dead: Int32 = -1

  /// The state before any byte.
  let start: Int

  private var nfa = NFA()
  private var subsets: [[Int]] = [], subsetIndex: [[Int]: Int] = [:]
  private var transitions: [[Int32]] = [], accepting: [Bool] = []
  private let acceptState: Int

  init(_ pattern: BytePattern) {
    let fragment = nfa.compile(pattern)
    acceptState = fragment.end
    start = 0
    _ = state(for: nfa.closure([fragment.start]))
  }

  /// Whether the text that led to `state` is a whole match.
  func isAccepting(_ state: Int) -> Bool { accepting[state] }

  /// The state after `byte`, or `nil` when no match can follow.
  func step(_ state: Int, _ byte: UInt8) -> Int? {
    var next = transitions[state][Int(byte)]
    if next == Self.unknown {
      let targets = subsets[state].flatMap { nfa.targets(of: $0, on: byte) }
      next = targets.isEmpty ? Self.dead : Int32(self.state(for: nfa.closure(targets)))
      transitions[state][Int(byte)] = next
    }
    return next == Self.dead ? nil : Int(next)
  }

  /// The state after every byte of `bytes`, or `nil` when no match can follow.
  func step(_ state: Int, _ bytes: some Sequence<UInt8>) -> Int? {
    var current = state
    for byte in bytes {
      guard let next = step(current, byte) else { return nil }
      current = next
    }
    return current
  }

  private func state(for subset: [Int]) -> Int {
    if let known = subsetIndex[subset] { return known }
    let index = subsets.count
    subsets.append(subset)
    subsetIndex[subset] = index
    transitions.append(Array(repeating: Self.unknown, count: 256))
    accepting.append(subset.contains(acceptState))
    return index
  }
}

/// A Thompson automaton: each state has ε-edges and byte-set edges.
private struct NFA {
  private var epsilon: [[Int]] = [], edges: [[(ByteSet, Int)]] = []

  mutating func compile(_ pattern: BytePattern) -> (start: Int, end: Int) {
    switch pattern {
      case .byte(let set):
        let (start, end) = (newState(), newState())
        edges[start].append((set, end))
        return (start, end)
      case .sequence(let parts):
        let start = newState()
        var end = start
        for part in parts {
          let fragment = compile(part)
          epsilon[end].append(fragment.start)
          end = fragment.end
        }
        return (start, end)
      case .either(let alternatives):
        let (start, end) = (newState(), newState())
        for alternative in alternatives {
          let fragment = compile(alternative)
          epsilon[start].append(fragment.start)
          epsilon[fragment.end].append(end)
        }
        return (start, end)
      case .repeated(let part, let minimum, let maximum):
        return compileRepetition(part, minimum: minimum, maximum: maximum)
    }
  }

  private mutating func compileRepetition(_ part: BytePattern, minimum: Int, maximum: Int?)
    -> (start: Int, end: Int)
  {
    let start = newState()
    var end = start
    for _ in 0..<minimum {
      let fragment = compile(part)
      epsilon[end].append(fragment.start)
      end = fragment.end
    }
    guard let maximum else {
      let loop = compile(part)
      epsilon[end].append(loop.start)
      epsilon[loop.end].append(loop.start)
      let exit = newState()
      epsilon[end].append(exit)
      epsilon[loop.end].append(exit)
      return (start, exit)
    }
    let exit = newState()
    epsilon[end].append(exit)
    for _ in minimum..<max(minimum, maximum) {
      let fragment = compile(part)
      epsilon[end].append(fragment.start)
      end = fragment.end
      epsilon[end].append(exit)
    }
    return (start, exit)
  }

  /// Every state reachable from `states` by ε-edges, sorted.
  func closure(_ states: [Int]) -> [Int] {
    var seen = Set(states), stack = states
    while let state = stack.popLast() {
      for next in epsilon[state] where seen.insert(next).inserted { stack.append(next) }
    }
    return seen.sorted()
  }

  func targets(of state: Int, on byte: UInt8) -> [Int] {
    edges[state].compactMap { $0.0.contains(byte) ? $0.1 : nil }
  }

  private mutating func newState() -> Int {
    epsilon.append([])
    edges.append([])
    return epsilon.count - 1
  }
}
