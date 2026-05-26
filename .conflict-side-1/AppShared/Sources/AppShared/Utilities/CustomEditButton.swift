//
//  CustomEditButton.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 30.12.25.
//

import SwiftUI

public struct CustomEditButton: View {
  @Environment(\.editMode) private var editMode

  public var body: some View {
    if #available(iOS 26.0, *) {
      if editMode?.wrappedValue.isEditing == true {
        Button(.app(.done), systemImage: "checkmark") {
          editMode?.wrappedValue = .inactive
        }
        .buttonStyle(.glassProminent)
      } else {
        Button(.app(.done), systemImage: "pencil") {
          editMode?.wrappedValue = .active
        }
      }
    } else {
      if editMode?.wrappedValue.isEditing == true {
        Button(.app(.done)) {
          editMode?.wrappedValue = .inactive
        }
        .bold()
      } else {
        Button(.app(.edit)) {
          editMode?.wrappedValue = .active
        }
      }
    }
  }
}
