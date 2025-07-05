//
//  DocumentedError.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 14.12.2024.
//

import Foundation

protocol DocumentedError {
  var documentationLink: URL? { get }
}
