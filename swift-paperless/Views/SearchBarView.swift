//
//  SearchBarView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 12.03.23.
//

import SwiftUI

struct SearchBarView: View {
    @Binding var text: String
    var cancelEnabled = true
    var isFocused: Binding<Bool>? = nil
    var onSubmit: () -> Void = {}

    @Environment(\.colorScheme) private var colorScheme

    @FocusState private var focused: Bool
    @State private var showCancel: Bool = false

    var barColor: Color {
        if colorScheme == .dark {
            return Color.secondarySystemGroupedBackground
        } else {
            return Color.systemGroupedBackground
        }
    }

    var body: some View {
        HStack {
            HStack {
                Label(String(localized: .localizable.search), systemImage: "magnifyingglass")
                    .labelStyle(.iconOnly)
                    .foregroundColor(.gray)
                    .padding(.trailing, -2)
                TextField(String(localized: .localizable.search), text: $text)
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
                    Label(String(localized: .localizable.searchClear), systemImage: "xmark.circle.fill")
                        .labelStyle(.iconOnly)
                        .foregroundColor(.gray)
                        .onTapGesture {
                            focused.toggle()
                            text = ""
                        }
                }
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
                    Text(.localizable.cancel)
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

        .onChange(of: focused) { newValue in
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
    @State private var text: String = ""
    @State private var hidden = false

    var content: (Binding<String>) -> Content

    var body: some View {
        content($text)
    }
}

#Preview("SearchBarView") {
    PreviewHelper { $text in
        NavigationStack {
            VStack {
                SearchBarView(text: $text)
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
                SearchBarView(text: $text, cancelEnabled: false)
                Spacer()
            }
            .padding()
        }
    }
}
