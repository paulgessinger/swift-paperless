//
//  InactiveView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 11.02.2024.
//

import SwiftUI

struct InactiveView: View {
    var body: some View {
        VStack {
            Spacer()
            Image(systemName: "leaf.fill")
                .foregroundColor(.white)
                .scaleEffect(5)
                .shadow(radius: 10)
                .padding(.bottom, 200)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(gradient: Gradient(colors: [.accentColor, Color("AccentColorDarkened")]), startPoint: .topLeading, endPoint: .bottomTrailing)
        )
    }
}

#Preview {
    InactiveView()
}
