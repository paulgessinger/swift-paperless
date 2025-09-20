//
//  Label+init.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 06.05.2024.
//

import SwiftUI

extension Label where Icon == Image, Title == Text {
  init(localized: LocalizedStringResource, systemImage: String) {
    self.init(String(localized: localized), systemImage: systemImage)
  }

  init(markdown: LocalizedStringResource, systemImage: String) {
    self.init(title: { Text(markdown) }, icon: { Image(systemName: systemImage) })
  }

  init(localized: LocalizedStringResource, image: String) {
    self.init(String(localized: localized), image: image)
  }
}

struct TightLabel: LabelStyle {
  func makeBody(configuration: Configuration) -> some View {
    HStack(spacing: 2) {
      configuration.icon
      configuration.title
    }
  }
}
