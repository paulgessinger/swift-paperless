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
        }
        else {
            return Color.systemGroupedBackground
        }
    }

    var body: some View {
        HStack {
            HStack {
                Label("Search", systemImage: "magnifyingglass")
                    .labelStyle(.iconOnly)
                    .foregroundColor(.gray)
                    .padding(.trailing, -2)
                TextField("Search", text: $text)
                    .padding(.trailing, 4)
                    .padding(.leading, 0)
                    .padding(.vertical, 8)
                    .foregroundColor(text.isEmpty ? .gray : .primary)
                    .focused($focused)
                    .onSubmit(onSubmit)

                if !text.isEmpty {
                    Spacer()
                    Label("Clear search", systemImage: "xmark.circle.fill")
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
                if showCancel && cancelEnabled {
                    Text("Cancel")
                        .foregroundColor(.accentColor)
                        .onTapGesture {
                            focused = false
//                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            withAnimation(.easeInOut) {
                                text = ""
                                showCancel = false
                            }
//                        }
                        }
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }
        }
        .animation(.easeInOut, value: focused)
        .transition(.opacity)

        .onChange(of: focused) { newValue in
            if let isFocused = isFocused {
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

struct PreviewWrapper: View {
    @State var text: String = ""
    @State var hidden = false

    var body: some View {
        NavigationStack {
            VStack {
                SearchBarView(text: $text)
                Text(String("Toggle")).onTapGesture {
                    Task {
                        withAnimation {
                            hidden.toggle()
                        }
                    }
                }
                Spacer()
            }
            .toolbar(hidden ? .hidden : .automatic)
        }
    }
}

struct SearchBarView_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            PreviewWrapper()
                .padding()
            Spacer()
        }
    }
}
