//
//  IconColorLabelStyle.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 20.01.26.
//

import SwiftUI

struct IconTintLabelStyle: LabelStyle {
  private let color: Color

  init(_ color: Color) {
    self.color = color
  }

  func makeBody(configuration: Configuration) -> some View {
    Label(
      title: { configuration.title },
      icon: { configuration.icon.foregroundStyle(color) }
    )
  }
}

extension LabelStyle where Self == IconTintLabelStyle {
  static func iconTint(_ color: Color) -> Self {
    IconTintLabelStyle(color)
  }
}
