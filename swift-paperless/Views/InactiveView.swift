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
                .resizable()
                .scaledToFit()
                .frame(width: 100, height: 100)
                .foregroundColor(.white)
                .shadow(radius: 10)
                .padding(.bottom, 100)
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
