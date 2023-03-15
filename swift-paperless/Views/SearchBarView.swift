//
//  SearchBarView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 12.03.23.
//

import SwiftUI

struct SearchBarView: View {
    @Binding var text: String

    @Environment(\.colorScheme) private var colorScheme

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
            Label("Search", systemImage: "magnifyingglass")
                .labelStyle(.iconOnly)
                .foregroundColor(.gray)
                .padding(.trailing, -2)
            TextField("Search", text: $text)
                .padding(.trailing, 4)
                .padding(.leading, 0)
                .padding(.vertical, 8)
                .foregroundColor(text.isEmpty ? .gray : .primary)
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
