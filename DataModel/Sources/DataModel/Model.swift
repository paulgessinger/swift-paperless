//
//  Model.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 18.02.23.
//

import Foundation
import SwiftUI

public protocol Model: Identifiable {
  var id: UInt { get }
}

public protocol Named {
  var name: String { get }
}
