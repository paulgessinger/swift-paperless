//
//  CustomEditButton.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 30.12.25.
//

import SwiftUI

struct SaveButton: View {

  let label: String
  let action: () -> Void

  init(_ label: String, action: @escaping () -> Void) {
    self.label = label
    self.action = action
  }

  init(_ label: LocalizedStringResource = .localizable(.save), action: @escaping () -> Void) {
    self.label = String(localized: label)
    self.action = action
  }

  var body: some View {
    if #available(iOS 26.0, *) {
      Button(label, systemImage: "checkmark", action: action)
      //            .buttonStyle(.glassProminent)
    } else {
      Button(label, action: action)
        .bold()
    }
  }
}
