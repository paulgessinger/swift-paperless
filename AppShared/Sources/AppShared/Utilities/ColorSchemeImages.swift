import Foundation
import RegexBuilder

extension String {
  /// Drops Markdown images meant for the other color scheme, following the docs
  /// site's `#only-light` / `#only-dark` URL fragments, so release notes show
  /// one screenshot per scheme in the app as on the web.
  ///
  /// An image on its own line goes with its line break, so a light/dark pair
  /// written on consecutive lines leaves a single image paragraph behind.
  public func keepingImages(dark: Bool) -> String {
    let hidden = dark ? "only-light" : "only-dark"
    let image = Regex {
      ZeroOrMore(CharacterClass.anyOf(" \t"))
      "!["
      ZeroOrMore(CharacterClass.anyOf("]").inverted)
      "]("
      ZeroOrMore(CharacterClass.anyOf(")#").inverted)
      "#\(hidden)"
      ")"
      Optionally {
        "{"
        ZeroOrMore(CharacterClass.anyOf("}").inverted)
        "}"
      }
      ZeroOrMore(CharacterClass.anyOf(" \t"))
      Optionally("\n")
    }
    return replacing(image, with: "")
  }
}
