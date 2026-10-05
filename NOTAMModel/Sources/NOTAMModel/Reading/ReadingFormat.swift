/**
 The compact text the on-device model writes for a NOTAM, and how it reads back into a
 ``NOTAMExtraction``.

 Every token the model emits costs a decode step, so it writes one line per runway direction and per
 obstacle, with only the facts the NOTAM states, rather than the schema's JSON. Model Training's
 `training/reading_format.py` writes the same format for the training targets; the two agree on every
 schema value.

 ```text
 CNL                         the NOTAM is a cancellation
 NIL                         nothing affects runway performance
 RWY <rwy|*> [CLSD [TKOF|LDG]] [PART [<len>] [END <end>]] [DTHR <len>] [TORA <len>] [LDA <len>]
     [SFC [CC <n>[/<n>/<n>]] <contaminant>[,<contaminant>…]|-]
 OBST [AGL <len>|MSL <len>] [DIST <len> DER <rwy>|THR <rwy>|ARP|OTHER] [DIR <compass>|<degrees>]
 ```

 `CLSD` alone closes the direction to both operations. A length is a number and its unit (`1713ft`,
 `0.125in`, `2.2nm`); a contaminant is its type with its coverage and depth when stated
 (`drySnow%30~0.125in`); `*` is the aerodrome. A distance is always followed by what it is measured
 from, and a direction is a 16-point compass word or a bare number of degrees.
 */
public enum ReadingFormat {
  static let canceled = "CNL", nothing = "NIL", aerodrome = "*", absent = "-"

  private static var measurement: Regex<(Substring, Substring, Substring)> {
    #/(\d+(?:\.\d+)?)(ft|m|nm|in|mm)/#
  }
  private static var contaminant: Regex<(Substring, Substring, Substring?, Substring?)> {
    #/([A-Za-z]+)(?:%(\d{1,3}))?(?:~(\S+))?/#
  }

  /// The extraction `text` states.
  ///
  /// - Throws: ``Malformed`` when `text` isn't in the format.
  public static func decode(_ text: String) throws(Malformed) -> NOTAMExtraction {
    switch text {
      case canceled: return .init(isCanceled: true, effects: [])
      case nothing: return .init(isCanceled: false, effects: [])
      default:
        var extraction = NOTAMExtraction(isCanceled: false, effects: [])
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
          var tokens = FieldTokens(line.split(separator: " ").map(String.init))
          if tokens.take("OBST") {
            extraction.obstacles.append(try obstacle(&tokens))
          } else {
            extraction.effects.append(try effect(&tokens))
          }
          guard tokens.isEmpty else { throw .unexpected(String(line)) }
        }
        return extraction
    }
  }

  private static func effect(_ tokens: inout FieldTokens) throws(Malformed)
    -> NOTAMExtraction.RunwayEffect
  {
    try tokens.expect("RWY")
    let runway = try tokens.next()
    var effect = NOTAMExtraction.RunwayEffect(
      runway: runway == aerodrome ? nil : runway,
      closure: .none
    )
    if tokens.take("CLSD") {
      effect.closure = tokens.take("TKOF") ? .takeoff : tokens.take("LDG") ? .landing : .both
    }
    if tokens.take("PART") {
      effect.partialClosure = .init(
        length: try tokens.peekIsMeasure ? length(tokens.next()) : nil,
        end: try tokens.take("END") ? tokens.next() : nil
      )
    }
    if tokens.take("DTHR") { effect.thresholdDisplacement = try length(tokens.next()) }
    let TORA = try tokens.take("TORA") ? length(tokens.next()) : nil,
      LDA = try tokens.take("LDA") ? length(tokens.next()) : nil
    if TORA != nil || LDA != nil { effect.declaredDistances = .init(TORA: TORA, LDA: LDA) }
    if tokens.take("SFC") { effect.surfaceCondition = try surfaceCondition(&tokens) }
    return effect
  }

  private static func surfaceCondition(_ tokens: inout FieldTokens) throws(Malformed)
    -> NOTAMExtraction.SurfaceCondition
  {
    var rwyCC: [Int]?
    if tokens.take("CC") {
      let codes = try tokens.next().split(separator: "/").map { Int($0) }
      guard !codes.isEmpty, codes.allSatisfy({ $0.map((0...6).contains) ?? false }) else {
        throw .unexpected("CC")
      }
      rwyCC = codes.compactMap(\.self)
    }
    let listed = try tokens.next()
    guard listed != absent else { return .init(rwyCC: rwyCC, contaminants: []) }
    var contaminants: [NOTAMExtraction.Contaminant] = []
    for text in listed.split(separator: ",") { contaminants.append(try contaminant(text)) }
    return .init(rwyCC: rwyCC, contaminants: contaminants)
  }

  private static func contaminant(_ text: Substring) throws(Malformed)
    -> NOTAMExtraction.Contaminant
  {
    guard let match = try? contaminant.wholeMatch(in: text),
      let type = NOTAMExtraction.ContaminantType(rawValue: String(match.1))
    else { throw .unexpected(String(text)) }
    let coveragePercent = match.2.flatMap { Int($0) }
    if let coveragePercent, coveragePercent > 100 { throw .unexpected(String(text)) }
    return .init(
      type: type,
      coveragePercent: coveragePercent,
      depth: try match.3.map { text throws(Malformed) in try depth(String(text)) }
    )
  }

  private static func obstacle(_ tokens: inout FieldTokens) throws(Malformed)
    -> NOTAMExtraction.Obstacle
  {
    var obstacle = NOTAMExtraction.Obstacle(
      height: nil,
      distance: nil,
      reference: nil,
      direction: nil
    )
    let datum: NOTAMExtraction.HeightDatum? =
      tokens.take("AGL") ? .AGL : tokens.take("MSL") ? .MSL : nil
    if let datum {
      let height = try length(tokens.next())
      obstacle.height = .init(value: height.value, unit: height.unit, datum: datum)
    }
    if tokens.take("DIST") {
      obstacle.distance = try distance(tokens.next())
      obstacle.reference = try reference(&tokens)
    }
    if tokens.take("DIR") { obstacle.direction = try direction(tokens.next()) }
    return obstacle
  }

  private static func reference(_ tokens: inout FieldTokens) throws(Malformed)
    -> NOTAMExtraction.ObstacleReference
  {
    switch try tokens.next() {
      case "DER": .init(kind: .departureEnd, runway: try tokens.next())
      case "THR": .init(kind: .threshold, runway: try tokens.next())
      case "ARP": .init(kind: .ARP, runway: nil)
      case "OTHER": .init(kind: .other, runway: nil)
      case let tag: throw .unexpected(tag)
    }
  }

  private static func direction(_ text: String) throws(Malformed)
    -> NOTAMExtraction.ObstacleDirection
  {
    if let point = NOTAMExtraction.CompassPoint(rawValue: text) { return .compass(point) }
    guard let degrees = Double(text), (0..<360).contains(degrees) else {
      throw .unexpected(text)
    }
    return .degrees(degrees)
  }
}

extension ReadingFormat {
  /// Whether `text` is a number and a unit.
  fileprivate static func isMeasure(_ text: String) -> Bool {
    (try? measurement.wholeMatch(in: text)) != nil
  }

  private static func measured(_ text: String) throws(Malformed) -> (value: Double, unit: Substring)
  {
    guard let match = try? measurement.wholeMatch(in: text), let value = Double(match.1), value > 0
    else {
      throw .unexpected(text)
    }
    return (value, match.2)
  }

  private static func length(_ text: String) throws(Malformed) -> NOTAMExtraction.Length {
    let (value, unit) = try measured(text)
    guard let unit = NOTAMExtraction.LengthUnit(rawValue: String(unit)) else {
      throw .unexpected(text)
    }
    return .init(value: value, unit: unit)
  }

  private static func depth(_ text: String) throws(Malformed) -> NOTAMExtraction.Depth {
    let (value, unit) = try measured(text)
    guard let unit = NOTAMExtraction.DepthUnit(rawValue: String(unit)) else {
      throw .unexpected(text)
    }
    return .init(value: value, unit: unit)
  }

  private static func distance(_ text: String) throws(Malformed) -> NOTAMExtraction.Distance {
    let (value, unit) = try measured(text)
    guard let unit = NOTAMExtraction.DistanceUnit(rawValue: String(unit)) else {
      throw .unexpected(text)
    }
    return .init(value: value, unit: unit)
  }
}

extension ReadingFormat {
  /// Text the on-device model wrote that isn't in ``ReadingFormat``.
  public enum Malformed: Error, Equatable, Sendable {
    /// A token that doesn't belong where it appears.
    case unexpected(String)
    /// The line ended where a value belongs.
    case truncated
  }
}

/// One line's tokens, read front to back.
private struct FieldTokens {
  private var tokens: ArraySlice<String>

  var isEmpty: Bool { tokens.isEmpty }

  /// Whether the next token is a number and a unit.
  var peekIsMeasure: Bool { tokens.first.map(ReadingFormat.isMeasure) ?? false }

  init(_ tokens: [String]) { self.tokens = tokens[...] }

  mutating func next() throws(ReadingFormat.Malformed) -> String {
    guard let token = tokens.popFirst() else { throw .truncated }
    return token
  }

  mutating func take(_ tag: String) -> Bool {
    guard tokens.first == tag else { return false }
    tokens.removeFirst()
    return true
  }

  mutating func expect(_ tag: String) throws(ReadingFormat.Malformed) {
    guard take(tag) else { throw tokens.first.map { .unexpected($0) } ?? .truncated }
  }
}
