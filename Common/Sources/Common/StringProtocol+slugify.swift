// Adapted from
// https://bootstragram.com/blog/slugify-in-swift/

import Foundation

public extension StringProtocol {
    func slugify() -> String {
        var slug = String(self)

        slug = slug.applyingTransform(.toLatin, reverse: false) ?? slug
        slug = slug.applyingTransform(.stripDiacritics, reverse: false) ?? slug
        slug = slug.applyingTransform(.stripCombiningMarks, reverse: false) ?? slug
        slug = slug.replacingOccurrences(of: "[^a-zA-Z0-9 ]+", with: "-", options: .regularExpression)
        slug = slug.trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        if !isEmpty, slug.isEmpty {
            if let extendedSelf = applyingTransform(.toUnicodeName, reverse: false)?
                .replacingOccurrences(of: "\\N", with: ""), self != extendedSelf
            {
                return extendedSelf.slugify()
            }
        }
        return slug
    }
}
