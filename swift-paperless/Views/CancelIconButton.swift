//
//  CancelIconButton.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 27.07.2024.
//

import SwiftUI

struct CancelIconButton: View {
  @Environment(\.dismiss) private var dismiss

  var action: (() -> Void)? = nil

  var body: some View {
    if #available(iOS 26, *) {
      Button {
        if let action {
          action()
        } else {
          dismiss()
        }
      } label: {
        Image(systemName: "xmark")
          .accessibilityLabel(Text(.localizable(.back)))
      }
    } else {
      Label(.localizable(.back), systemImage: "xmark.circle.fill")
        .labelStyle(.iconOnly)
        .symbolRenderingMode(.palette)
        .foregroundStyle(.primary, .tertiary)
        .font(.title2)

        .onTapGesture {
          if let action {
            action()
          } else {
            dismiss()
          }
        }
    }
  }
}

#Preview {
  CancelIconButton()
}
