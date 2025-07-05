//
//  Binding.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 24.04.2024.
//

import SwiftUI

extension Binding {
  static func present(_ base: Binding<(some Sendable)?>) -> Binding<Bool> where Value == Bool {
    .init(get: { base.wrappedValue != nil }, set: { if !$0 { base.wrappedValue = nil } })
  }

  init(present base: Binding<(some Sendable)?>) where Value == Bool {
    self.init(get: { base.wrappedValue != nil }, set: { if !$0 { base.wrappedValue = nil } })
  }
}
