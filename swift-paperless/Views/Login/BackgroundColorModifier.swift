//
//  BackgroundColorModifier.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 04.02.25.
//

import SwiftUI

struct BackgroundColorModifier: ViewModifier {
  @Environment(\.colorScheme) private var colorScheme

  func body(content: Content) -> some View {
    #if canImport(UIKit)
      content
        .background(Color(uiColor: .systemGroupedBackground))
    #else
      content
    #endif
  }
}
