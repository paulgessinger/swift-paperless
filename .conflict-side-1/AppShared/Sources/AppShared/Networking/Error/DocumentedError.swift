//
//  DocumentedError.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 14.12.2024.
//

import Foundation

public protocol DocumentedError {
  var documentationLink: URL? { get }
}
