//
//  SearchBarView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 12.03.23.
//

import SwiftUI

public struct SearchBarViewiOS18: View {
  @Binding public var text: String
  public var cancelEnabled = true
  public var isFocused: Binding<Bool>? = nil
  public var isLoading: Bool = false
  public var onSubmit: () -> Void = {}

  public init(
    text: Binding<String>, cancelEnabled: Bool = true, isFocused: Binding<Bool>? = nil,
    isLoading: Bool = false, onSubmit: @escaping () -> Void = {}
  ) {
    self._text = text
    self.cancelEnabled = cancelEnabled
    self.isFocused = isFocused
    self.isLoading = isLoading
    self.onSubmit = onSubmit
  }

  @Environment(\.colorScheme) private var colorScheme

  @FocusState private var focused: Bool
  @State private var showCancel: Bool = false

  public var barColor: AnyShapeStyle {
    if colorScheme == .dark {
      .init(.background.secondary)
    } else {
      .init(.background.tertiary)
    }
  }

  public var body: some View {
    HStack {
      HStack {
        Label(String(localized: .localizable(.search)), systemImage: "magnifyingglass")
          .labelStyle(.iconOnly)
          .foregroundColor(.gray)
          .padding(.trailing, -2)
        TextField(String(localized: .localizable(.search)), text: $text)
          .padding(.trailing, 4)
          .padding(.leading, 0)
          .padding(.vertical, 8)
          .foregroundColor(text.isEmpty ? .gray : .primary)
          .focused($focused)
          .onSubmit(onSubmit)
          .autocorrectionDisabled()
          .textInputAutocapitalization(.never)

        if !text.isEmpty {
          Spacer()
          Label(String(localized: .localizable(.searchClear)), systemImage: "xmark.circle.fill")
            .labelStyle(.iconOnly)
            .foregroundColor(.gray)
            .onTapGesture {
              text = ""
            }
        }

        ProgressView()
          .controlSize(.regular)
          .opacity(isLoading ? 1 : 0)
          .animation(.default, value: isLoading)
      }
      .padding(.horizontal, 10)
      .background(
        Rectangle()
          //                    .fill(barColor)
          .fill(.ultraThinMaterial)
          .cornerRadius(10)
      )

      Group {
        if showCancel, cancelEnabled {
          Text(.localizable(.cancel))
            .foregroundColor(.accentColor)
            .onTapGesture {
              focused = false
              withAnimation(.easeInOut) {
                text = ""
                showCancel = false
              }
            }
            .transition(.opacity.combined(with: .move(edge: .trailing)))
        }
      }
    }
    .animation(.easeInOut, value: focused)
    .transition(.opacity)

    .onChange(of: focused) { _, newValue in
      if let isFocused {
        isFocused.wrappedValue = newValue
      }

      if newValue {
        withAnimation(.easeInOut) {
          showCancel = true
        }
      }
    }
  }
}

private struct PreviewHelper<Content>: View where Content: View {
  @State private var text = ""
  @State private var hidden = false

  public var content: (Binding<String>) -> Content

  public var body: some View {
    content($text)
  }
}

#Preview("SearchBarView") {
  PreviewHelper { $text in
    NavigationStack {
      VStack {
        SearchBarViewiOS18(text: $text)
        Spacer()
      }
      .padding()
    }
  }
}

#Preview("SearchBarView (No cancel)") {
  PreviewHelper { $text in
    NavigationStack {
      VStack {
        SearchBarViewiOS18(text: $text, cancelEnabled: false)
        Spacer()
      }
      .padding()
    }
  }
}
