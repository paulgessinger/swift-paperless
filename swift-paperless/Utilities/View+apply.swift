//
//  View+if.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 22.09.2024.
//

import SwiftUI

extension View {
  /// Applies the given transform if the given condition evaluates to `true`.
  /// - Parameters:
  ///   - condition: The condition to evaluate.
  ///   - transform: The transform to apply to the source `View`.
  /// - Returns: Either the original `View` or the modified `View` if the condition is `true`.
  func apply(@ViewBuilder _ transform: (Self) -> some View) -> some View {
    transform(self)
  }
}
