//
//  String+stripMarkdown.swift
//  Common
//
//  Created by Paul Gessinger on 21.06.25.
//

import Foundation

public extension String {
    func stripMarkdown() -> String {
        if let str = try? AttributedString(markdown: self) {
            String(str.characters)
        } else {
            self
        }
    }
}
