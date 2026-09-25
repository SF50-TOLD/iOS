/// The contaminant words of FAA FICON, Canadian RSC and ICAO SNOWTAM reports, per the Model Training
/// `SCHEMA.md` vocabulary table.
enum ContaminantVocabulary {
  typealias ContaminantType = NOTAMExtraction.ContaminantType

  /// A surface report's word for "no contaminant".
  static let dry = ["DRY"]

  private static let layerSeparators = [["OVER"], ["ON", "TOP", "OF"]]

  private static let singleLayers: [(words: [String], type: ContaminantType)] = [
    (["WET"], .wet),
    (["WATER"], .water),
    (["STANDING", "WATER"], .water),
    (["SLUSH"], .slush),
    (["WET", "SN"], .wetSnow),
    (["WET", "SNOW"], .wetSnow),
    (["DRY", "SN"], .drySnow),
    (["DRY", "SNOW"], .drySnow),
    (["COMPACTED", "SN"], .compactedSnow),
    (["COMPACTED", "SNOW"], .compactedSnow),
    (["FROST"], .frost),
    (["ICE"], .ice),
    (["WET", "ICE"], .wetIce),
    (["DAMP"], .other),
    (["MUD"], .other),
    (["SLIPPERY", "WET"], .other),
    (["COMPACTED", "SNOW", "GRAVEL", "MIX"], .other),
    (["COMPACTED", "SN", "GRAVEL", "MIX"], .other),
    (["COMPACTED", "SNOW/GRAVEL", "MIX"], .other)
  ]

  private static let layered: [ContaminantType: [ContaminantType: ContaminantType]] = [
    .slush: [.ice: .slushOverIce],
    .water: [.compactedSnow: .waterOverCompactedSnow],
    .drySnow: [.compactedSnow: .drySnowOverCompactedSnow, .ice: .drySnowOverIce],
    .wetSnow: [.compactedSnow: .wetSnowOverCompactedSnow, .ice: .wetSnowOverIce]
  ]

  /// Reads the longest contaminant phrase at the cursor, layered (`DRY SN OVER COMPACTED SN`) or
  /// single, or returns `nil` and leaves the cursor where it was.
  static func read(from cursor: inout TokenCursor) -> ContaminantType? {
    let start = cursor
    guard let top = readSingleLayer(from: &cursor) else { return nil }
    let beforeSeparator = cursor
    guard layerSeparators.contains(where: { cursor.consume($0) }) else { return top }
    _ = cursor.consume(["PATCHY"])
    guard let bottom = readSingleLayer(from: &cursor) else {
      cursor = beforeSeparator
      return top
    }
    guard top != .other, bottom != .other else {
      cursor = start
      return nil
    }
    return layered[top]?[bottom] ?? .other
  }

  private static func readSingleLayer(from cursor: inout TokenCursor) -> ContaminantType? {
    let match = singleLayers.filter { cursor.hasPrefix($0.words) }.max {
      $0.words.count < $1.words.count
    }
    guard let match else { return nil }
    cursor.advance(by: match.words.count)
    return match.type
  }
}
