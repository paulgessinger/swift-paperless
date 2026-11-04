//
//  Binding.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 24.04.2024.
//

import AppShared
import SwiftUI

extension Binding {
  public static func present(_ base: Binding<(some Sendable)?>) -> Binding<Bool>
  where Value == Bool {
    .init(get: { base.wrappedValue != nil }, set: { if !$0 { base.wrappedValue = nil } })
  }

  public init(present base: Binding<(some Sendable)?>) where Value == Bool {
    self.init(get: { base.wrappedValue != nil }, set: { if !$0 { base.wrappedValue = nil } })
  }

  /// Reads `nil` as `defaultValue`, for settings that also record "not decided yet".
  public init(_ base: Binding<Value?>, default defaultValue: Value) where Value: Sendable {
    self.init(get: { base.wrappedValue ?? defaultValue }, set: { base.wrappedValue = $0 })
  }
}
