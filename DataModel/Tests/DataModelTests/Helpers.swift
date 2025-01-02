//
//  Helpers.swift
//  DataModel
//
//  Created by Paul Gessinger on 02.01.25.
//

import Foundation

func testData(_ file: String) -> Data? {
    guard let rel = URL(string: file) else {
        return nil
    }
    guard let url = Bundle.module.url(forResource: rel.deletingPathExtension().absoluteString, withExtension: ".\(rel.pathExtension)") else {
        return nil
    }

    do {
        return try Data(contentsOf: url)
    } catch {
        return nil
    }
}
