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
    var onSubmit: () -> Void = {}

    @Environment(\.colorScheme) private var colorScheme

    @FocusState private var focused: Bool
    @State private var showCancel: Bool = false

    var textColor: Color {
        if colorScheme == .dark {
            return Color.green
        }
        else {
            return Color.red
        }
    }

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
                    Label("Clear", systemImage: "xmark.circle.fill")
                        .labelStyle(.iconOnly)
                        .foregroundColor(.gray)
                        .onTapGesture {
                            text = ""
                        }
                }
            }
            .padding(.horizontal, 10)
            .background(
                Rectangle()
                    .fill(barColor)
                    .cornerRadius(10)
            )

            Group {
                if showCancel && cancelEnabled {
                    Button("Cancel") {
                        focused = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            text = ""
                            withAnimation {
                                showCancel = false
                            }
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }
        }
        .animation(.easeInOut, value: focused)
        .transition(.opacity)

        .onChange(of: focused) { newValue in
            if newValue {
                withAnimation {
                    showCancel = true
                }
            }
        }
    }
}

struct PreviewWrapper: View {
    @State var text: String = ""

    var body: some View {
        SearchBarView(text: $text)
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
