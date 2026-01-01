//
//  CustomEditButton.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 30.12.25.
//

import SwiftUI

struct CustomEditButton: View {
  @Environment(\.editMode) private var editMode

  var body: some View {
    if #available(iOS 26.0, *) {
      if editMode?.wrappedValue.isEditing == true {
        Button(.localizable(.done), systemImage: "checkmark") {
          editMode?.wrappedValue = .inactive
        }
        .buttonStyle(.glassProminent)
      } else {
        Button(.localizable(.done), systemImage: "pencil") {
          editMode?.wrappedValue = .active
        }
      }
    } else {
      if editMode?.wrappedValue.isEditing == true {
        Button(.localizable(.done)) {
          editMode?.wrappedValue = .inactive
        }
        .bold()
      } else {
        Button(.localizable(.edit)) {
          editMode?.wrappedValue = .active
        }
      }
    }
  }
}
