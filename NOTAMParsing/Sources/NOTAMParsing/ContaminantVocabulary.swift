internal import RegexBuilder

/// The contaminant words of FAA FICON, Canadian RSC and ICAO SNOWTAM reports.
final class ContaminantVocabulary {
  typealias ContaminantType = FormattedReport.ContaminantType

  private static let singleLayers: [String: ContaminantType] = [
    "WET": .wet,
    "WATER": .water,
    "STANDING WATER": .water,
    "SLUSH": .slush,
    "WET SN": .wetSnow,
    "WET SNOW": .wetSnow,
    "DRY SN": .drySnow,
    "DRY SNOW": .drySnow,
    "COMPACTED SN": .compactedSnow,
    "COMPACTED SNOW": .compactedSnow,
    "FROST": .frost,
    "ICE": .ice,
    "WET ICE": .wetIce,
    "DAMP": .other,
    "MUD": .other,
    "SLIPPERY WET": .other,
    "COMPACTED SNOW GRAVEL MIX": .other,
    "COMPACTED SN GRAVEL MIX": .other,
    "COMPACTED SNOW/GRAVEL MIX": .other
  ]

  private static let layerSeparators = ["OVER", "ON TOP OF"]

  private static let layered: [ContaminantType: [ContaminantType: ContaminantType]] = [
    .slush: [.ice: .slushOverIce],
    .water: [.compactedSnow: .waterOverCompactedSnow],
    .drySnow: [.compactedSnow: .drySnowOverCompactedSnow, .ice: .drySnowOverIce],
    .wetSnow: [.compactedSnow: .wetSnowOverCompactedSnow, .ice: .wetSnowOverIce]
  ]

  /// A contaminant phrase: one layer, or two (`DRY SN OVER COMPACTED SN`). Of the phrases that
  /// could match, the longest does.
  private(set) lazy var phrase = Regex {
    singleLayer
    Optionally {
      " "
      ReportGrammar.alternation(of: Self.layerSeparators)
      " "
      Optionally("PATCHY ")
      singleLayer
    }
  }

  private lazy var singleLayer = Regex {
    ReportGrammar.alternation(of: Self.longestFirst(Self.singleLayers.keys))
    ReportGrammar.tokenEnd
  }

  /// The contaminant a phrase `phrase` matched names, or `nil` when it layers a contaminant the
  /// vocabulary doesn't name.
  static func type(of phrase: Substring) -> ContaminantType? {
    guard let (top, bottom) = layers(of: phrase) else { return singleLayers[String(phrase)] }
    guard let top = singleLayers[String(top)], let bottom = singleLayers[String(bottom)],
      top != .other, bottom != .other
    else { return nil }
    return layered[top]?[bottom] ?? .other
  }

  private static func longestFirst(_ phrases: some Sequence<String>) -> [String] {
    phrases.sorted { ($1.split(separator: " ").count, $0) < ($0.split(separator: " ").count, $1) }
  }

  private static func layers(of phrase: Substring) -> (top: Substring, bottom: Substring)? {
    for separator in layerSeparators {
      guard let range = phrase.firstRange(of: " \(separator) ") else { continue }
      let bottom = phrase[range.upperBound...]
      return (phrase[..<range.lowerBound], bottom.trimmingPrefix("PATCHY "))
    }
    return nil
  }
}
