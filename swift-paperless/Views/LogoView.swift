//
//  LogoView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 25.03.23.
//

import SwiftUI

struct LogoView: View {
    private let logoSize: CGFloat = 64
    private let logoRadius: CGFloat = 5

    var body: some View {
        VStack(spacing: -15) {
            Image(.appLogoTransparent)
            Text(.localizable(.appName))
                .font(.title)
        }
    }
}

struct LogoTitle: View {
    @ScaledMetric(relativeTo: .body) private var logoSize = 50.0

    var body: some View {
        HStack(spacing: 5) {
            Image(.appLogoTransparent)
                .resizable()
                .frame(width: logoSize, height: logoSize)
            Text(.localizable(.appName))
                .font(.title2)
        }
        .padding(.trailing, 15)
    }
}

#Preview {
    NavigationStack {
        LogoView()
            .toolbar {
                ToolbarItem(placement: .principal) {
                    LogoTitle()
                }
            }
    }
}
