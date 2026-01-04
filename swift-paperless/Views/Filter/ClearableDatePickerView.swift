//
//  ClearableDatePickerView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 03.01.26.
//

import SwiftUI

struct ClearableDatePickerView: View {
  @Binding var value: Date?

  var body: some View {
    HStack {
      if let unwrapped = Binding(unwrapping: $value) {
        DatePicker(selection: unwrapped, displayedComponents: .date) {
          Image(systemName: "xmark.circle.fill")
            .foregroundColor(.secondary)
            .accessibilityLabel(String(localized: .localizable(.dateClear)))
            .contentShape(Rectangle())
            .frame(maxWidth: .infinity, alignment: .trailing)
            .onTapGesture {
              value = nil
            }
        }
      } else {
        HStack {
          Image(systemName: "plus.circle.fill")
          Text(.localizable(.dateAdd))
        }
        .foregroundColor(.accentColor)
        .onTapGesture {
          value = .now
        }
      }
    }
    .animation(.spring, value: value)
  }
}
