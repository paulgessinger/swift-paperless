//
//  String+isNumber.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 01.06.2024.
//

import Foundation

extension String {
  public var isNumber: Bool {
    let digitsCharacters = CharacterSet(charactersIn: "0123456789")
    return CharacterSet(charactersIn: self).isSubset(of: digitsCharacters)
  }
}
