//
//  ClearableDatePickerView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 03.01.26.
//

import SwiftUI

struct ClearableDatePickerView: View {
  @Binding var value: Date?
  let title: LocalizedStringResource?

  init(value: Binding<Date?>, title: LocalizedStringResource? = nil) {
    self._value = value
    self.title = title
  }

  var body: some View {
    HStack {
      Text(title ?? "")
        .frame(maxWidth: .infinity, alignment: .leading)
      if let unwrapped = Binding(unwrapping: $value) {
        Image(systemName: "xmark.circle.fill")
          .foregroundColor(.secondary)
          .accessibilityLabel(String(localized: .localizable(.dateClear)))
          .contentShape(Rectangle())
          .onTapGesture {
            value = nil
          }
        DatePicker(selection: unwrapped, displayedComponents: .date) {}
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

private struct ClearableDatePickerPreview: View {
  @State private var emptyValue: Date?
  @State private var setValue: Date?
  @State private var noTitleValue: Date?

  init() {
    _emptyValue = State(initialValue: nil)
    _setValue = State(initialValue: Date(timeIntervalSince1970: 0))
    _noTitleValue = State(initialValue: nil)
  }

  var body: some View {
    Form {
      Section("With Title") {
        ClearableDatePickerView(
          value: $emptyValue,
          title: "No Date Set"
        )
        ClearableDatePickerView(
          value: $setValue,
          title: "Date Set"
        )
      }
      Section("No Title") {
        ClearableDatePickerView(value: $noTitleValue)
      }
    }
  }
}

#Preview("ClearableDatePickerView") {
  ClearableDatePickerPreview()
}
