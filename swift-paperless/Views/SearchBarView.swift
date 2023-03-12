//
//  SearchBarView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 12.03.23.
//

import SwiftUI

struct SearchBarView: View {
    @Binding var text: String

    var body: some View {
        HStack {
            Label("Search", systemImage: "magnifyingglass")
                .labelStyle(.iconOnly)
            TextField("Search", text: $text)
                .padding(.horizontal, 4)
                .padding(.vertical, 10)
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
                .fill(Color.systemGroupedBackground)
                .cornerRadius(10)
        )
    }
}
