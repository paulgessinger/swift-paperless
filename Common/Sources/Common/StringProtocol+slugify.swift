// Adapted from
// https://www.mickf.net/tech/slugify-in-swift/

import Foundation

extension StringProtocol {
  public func slugify() -> String {
    var slug = String(self)

    slug = slug.applyingTransform(.toLatin, reverse: false) ?? slug
    slug = slug.applyingTransform(.stripDiacritics, reverse: false) ?? slug
    slug = slug.applyingTransform(.stripCombiningMarks, reverse: false) ?? slug
    slug = slug.replacingOccurrences(of: "[^a-zA-Z0-9 ]+", with: "-", options: .regularExpression)
    slug = slug.trimmingCharacters(in: CharacterSet(charactersIn: "-"))

    if !isEmpty, slug.isEmpty {
      let extendedSelf = applyingTransform(.toUnicodeName, reverse: false)?
        .replacingOccurrences(of: "\\N", with: "")
      if let extendedSelf, self != extendedSelf {
        return extendedSelf.slugify()
      }
    }
    return slug
  }
}
