/**
 The compact text the on-device model writes for a NOTAM, and how it reads back into a
 ``NOTAMExtraction``.

 Every token the model emits costs a decode step, so it writes one line per runway effect with only
 the facts the NOTAM states, rather than the schema's JSON. Model Training's
 `training/reading_format.py` writes the same format for the training targets; the two agree on every
 schema value.

 ```text
 CNL                         the NOTAM is a cancellation
 NIL                         nothing affects runway performance
 RWY <rwy|*> [CLSD [PART]] [LEN <len>] [END <end>] [DTHR <len>]
     [DD [TORA <len>] [TODA <len>] [ASDA <len>] [LDA <len>]]
     [SFC [CC <n>[/<n>…]] <contaminant>[,<contaminant>…]|-]
     [OBST [AGL <len>] [MSL <len>] [DIST <len>] [REF "<text>"] [BRG <n>] [POS <lat> <lon>]]
 ```

 A length is a number and its unit (`1713ft`, `0.125in`, `2.2nm`); a contaminant is its type with its
 third, coverage and depth when stated (`drySnowOverCompactedSnow@2%30~0.125in`); `*` is the aerodrome.
 A position is copied as the NOTAM writes it in degrees, minutes and seconds (`POS 453036N 0732322W`)
 and converted here, so the model never does the arithmetic; decimal degrees are read too.
 */
public enum ReadingFormat {
  static let canceled = "CNL", nothing = "NIL", aerodrome = "*", absent = "-"

  private static var measurement: Regex<(Substring, Substring, Substring)> {
    /(\d+(?:\.\d+)?)(ft|m|nm|in|mm)/
  }
  private static var contaminant: Regex<(Substring, Substring, Substring?, Substring?, Substring?)>
  {
    /([A-Za-z]+)(?:@([1-3]))?(?:%(\d{1,3}))?(?:~(\S+))?/
  }
  private static var token: Regex<Substring> { /"[^"]*"|\S+/ }

  /// The extraction `text` states.
  ///
  /// - Throws: ``Malformed`` when `text` isn't in the format.
  public static func decode(_ text: String) throws(Malformed) -> NOTAMExtraction {
    switch text {
      case canceled: return .init(isCanceled: true, effects: [])
      case nothing: return .init(isCanceled: false, effects: [])
      default:
        var effects: [NOTAMExtraction.RunwayEffect] = []
        for line in text.split(separator: "\n") { effects.append(try decodeEffect(line)) }
        return .init(isCanceled: false, effects: effects)
    }
  }

  private static func decodeEffect(_ line: Substring) throws(Malformed)
    -> NOTAMExtraction.RunwayEffect
  {
    var tokens = FieldTokens(line.matches(of: token).map { String($0.output) })
    try tokens.expect("RWY")
    let runway = try tokens.next()
    var effect = NOTAMExtraction.RunwayEffect(
      runway: runway == aerodrome ? nil : runway,
      closure: .none
    )
    if tokens.take("CLSD") { effect.closure = tokens.take("PART") ? .partial : .full }
    if tokens.take("LEN") { effect.closedLength = try length(tokens.next()) }
    if tokens.take("END") { effect.closedEnd = try tokens.next() }
    if tokens.take("DTHR") { effect.thresholdDisplacement = try length(tokens.next()) }
    if tokens.take("DD") {
      effect.declaredDistances = .init(
        TORA: try tokens.take("TORA") ? length(tokens.next()) : nil,
        TODA: try tokens.take("TODA") ? length(tokens.next()) : nil,
        ASDA: try tokens.take("ASDA") ? length(tokens.next()) : nil,
        LDA: try tokens.take("LDA") ? length(tokens.next()) : nil
      )
    }
    if tokens.take("SFC") { effect.surfaceCondition = try surfaceCondition(&tokens) }
    if tokens.take("OBST") { effect.obstacle = try obstacle(&tokens) }
    guard tokens.isEmpty else { throw .unexpected(String(line)) }
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
    let coveragePercent = match.3.flatMap { Int($0) }
    if let coveragePercent, coveragePercent > 100 { throw .unexpected(String(text)) }
    return .init(
      type: type,
      runwayThird: match.2.flatMap { Int($0) },
      coveragePercent: coveragePercent,
      depth: try match.4.map { text throws(Malformed) in try depth(String(text)) }
    )
  }

  private static func obstacle(_ tokens: inout FieldTokens) throws(Malformed)
    -> NOTAMExtraction.Obstacle
  {
    var obstacle = NOTAMExtraction.Obstacle()
    if tokens.take("AGL") { obstacle.heightAGL = try length(tokens.next()) }
    if tokens.take("MSL") { obstacle.heightMSL = try length(tokens.next()) }
    if tokens.take("DIST") { obstacle.distance = try distance(tokens.next()) }
    if tokens.take("REF") {
      let quoted = try tokens.next()
      guard quoted.count >= 2, quoted.hasPrefix("\""), quoted.hasSuffix("\"") else {
        throw .unexpected(quoted)
      }
      obstacle.distanceReference = String(quoted.dropFirst().dropLast())
    }
    if tokens.take("BRG") { obstacle.bearingDegrees = try number(tokens.next()) }
    if tokens.take("POS") {
      obstacle.latitude = try coordinate(tokens.next(), converting: DMSCoordinate.latitude)
      obstacle.longitude = try coordinate(tokens.next(), converting: DMSCoordinate.longitude)
    }
    return obstacle
  }
}

extension ReadingFormat {
  private static func number(_ text: String) throws(Malformed) -> Double {
    guard let value = Double(text), value.isFinite else { throw .unexpected(text) }
    return value
  }

  /// Decimal degrees, or degrees-minutes-seconds as the NOTAM wrote them (`453036N`), converted.
  private static func coordinate(_ text: String, converting dms: (String) -> Double?)
    throws(Malformed)
    -> Double
  {
    if let converted = dms(text) { return converted }
    return try number(text)
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

/// One effect line's tokens, read front to back.
private struct FieldTokens {
  private var tokens: ArraySlice<String>

  var isEmpty: Bool { tokens.isEmpty }

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
