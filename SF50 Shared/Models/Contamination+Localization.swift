public import Foundation

extension Contamination {
  /// How the condition reads wherever the app writes it down, so a runway row and a TLR report say
  /// the same thing about the same runway.
  ///
  /// Depth is given in inches, the unit the AFM contaminated-runway tables are written in.
  ///
  /// Resolve the resource before putting it in a string — hand it to a `Text`, or to
  /// `String(localized:)`. Interpolating the resource itself writes its debug description in place
  /// of the condition.
  public var localizedTitle: LocalizedStringResource {
    switch self {
      case .waterOrSlush(let depth):
        LocalizedStringResource(
          "Water/Slush \(depth.converted(to: .inches), format: .depth)",
          bundle: .sharedFramework,
          comment: "A runway condition. The argument is the depth of the water or slush, in inches."
        )
      case .slushOrWetSnow(let depth):
        LocalizedStringResource(
          "Slush/Wet Snow \(depth.converted(to: .inches), format: .depth)",
          bundle: .sharedFramework,
          comment:
            "A runway condition. The argument is the depth of the slush or wet snow, in inches."
        )
      case .drySnow:
        LocalizedStringResource(
          "Dry Snow",
          bundle: .sharedFramework,
          comment: "A runway condition."
        )
      case .compactSnow:
        LocalizedStringResource(
          "Compact Snow",
          bundle: .sharedFramework,
          comment: "A runway condition."
        )
      case .wetRunway:
        LocalizedStringResource(
          "Wet Runway",
          bundle: .sharedFramework,
          comment: "A runway condition."
        )
      case .rwyCC(let rwyCC):
        LocalizedStringResource(
          "RwyCC \(rwyCC, format: .number)",
          bundle: .sharedFramework,
          comment: "A runway condition. The argument is the runway condition code, 1 through 6."
        )
    }
  }

  /// The description as VoiceOver reads it aloud.
  ///
  /// The conditions that ``localizedTitle`` writes in symbols read differently aloud: “RwyCC”
  /// is an abbreviation with no pronunciation, so the spoken form spells the term out, and a depth’s
  /// prime is a mark voices disagree about, so the spoken form names the unit outright.
  public var accessibilityDescription: LocalizedStringResource {
    switch self {
      case .waterOrSlush(let depth):
        LocalizedStringResource(
          "Water/Slush \(depth.converted(to: .inches), format: .spokenDepth)",
          bundle: .sharedFramework,
          comment: "A runway condition. The argument is the depth of the water or slush, in inches."
        )
      case .slushOrWetSnow(let depth):
        LocalizedStringResource(
          "Slush/Wet Snow \(depth.converted(to: .inches), format: .spokenDepth)",
          bundle: .sharedFramework,
          comment:
            "A runway condition. The argument is the depth of the slush or wet snow, in inches."
        )
      case .rwyCC(let rwyCC):
        LocalizedStringResource(
          "Runway condition code \(rwyCC, format: .number)",
          bundle: .sharedFramework,
          comment:
            "A runway condition, spoken aloud. The argument is the runway condition code, 1 through 6."
        )
      case .drySnow, .compactSnow, .wetRunway:
        localizedTitle
    }
  }
}
