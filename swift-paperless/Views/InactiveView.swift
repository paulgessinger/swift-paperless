//
//  InactiveView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 11.02.2024.
//

import SwiftUI

struct InactiveView: View {
  var body: some View {
    VStack {}
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(
        LinearGradient(
          gradient: Gradient(colors: [.accentColor, Color(.accentColorDarkened)]),
          startPoint: .topLeading, endPoint: .bottomTrailing)
      )
  }
}

#Preview {
  InactiveView()
}
