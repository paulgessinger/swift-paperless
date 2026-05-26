//
//  CustomEditButton.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 30.12.25.
//

import SwiftUI

public struct SaveButton: View {

  public let label: String
  public let action: () -> Void

  public init(_ label: String, action: @escaping () -> Void) {
    self.label = label
    self.action = action
  }

  public init(_ label: LocalizedStringResource = .app(.save), action: @escaping () -> Void) {
    self.label = String(localized: label)
    self.action = action
  }

  public var body: some View {
    if #available(iOS 26.0, *) {
      Button(label, systemImage: "checkmark", action: action)
      //            .buttonStyle(.glassProminent)
    } else {
      Button(label, action: action)
        .bold()
    }
  }
}
