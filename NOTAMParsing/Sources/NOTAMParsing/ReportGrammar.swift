internal import RegexBuilder

/// Lexical pieces the report formats' grammars are built from.
///
/// Digits are ASCII only, so a run of them always converts to a number.
enum ReportGrammar {
  static var digit: CharacterClass { CharacterClass("0"..."9") }
  static var letter: CharacterClass { CharacterClass("A"..."Z") }
  static var alphanumeric: CharacterClass { CharacterClass("A"..."Z", "0"..."9") }

  /// A run of anything but spaces.
  static var word: Regex<Substring> { Regex { OneOrMore(CharacterClass.anyOf(" ").inverted) } }

  /// The end of a token, not consumed: a space, a slash, a comma, or the end of the text.
  static var tokenEnd: Lookahead<Substring> {
    Lookahead {
      ChoiceOf {
        CharacterClass.anyOf(" /,")
        Anchor.endOfSubject
      }
    }
  }

  /**
   A regex matching any one of `alternatives`, tried in the order given.

   `ChoiceOf` only takes a list known when the code is written, so a list built at run time is
   folded with the builder `ChoiceOf` uses. Each alternative is matched literally.
   */
  static func alternation(of alternatives: [String]) -> Regex<Substring> {
    guard let first = alternatives.first else {
      preconditionFailure("An alternation needs at least one alternative")
    }
    return alternatives.dropFirst().reduce(Regex { first }) { alternation, alternative in
      AlternationBuilder.buildPartialBlock(accumulated: alternation, next: alternative).regex
    }
  }
}
