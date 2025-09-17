//
//  String+stripMarkdown.swift
//  Common
//
//  Created by Paul Gessinger on 21.06.25.
//

import Foundation

extension String {
  public func stripMarkdown() -> String {
    if let str = try? AttributedString(markdown: self) {
      String(str.characters)
    } else {
      self
    }
  }
}
