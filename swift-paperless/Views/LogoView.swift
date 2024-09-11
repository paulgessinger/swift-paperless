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

#Preview {
    LogoView()
}
