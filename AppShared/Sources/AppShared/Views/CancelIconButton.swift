//
//  CancelIconButton.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 27.07.2024.
//

import SwiftUI

public struct CancelIconButton: View {
  @Environment(\.dismiss) private var dismiss

  public var action: (() -> Void)? = nil

  public init(action: (() -> Void)? = nil) {
    self.action = action
  }

  public var body: some View {
    if #available(iOS 26, *) {
      Button {
        if let action {
          action()
        } else {
          dismiss()
        }
      } label: {
        Image(systemName: "xmark")
          .accessibilityLabel(Text(.app(.back)))
      }
    } else {
      Label(.app(.back), systemImage: "xmark.circle.fill")
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
