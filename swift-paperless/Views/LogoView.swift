//
//  LogoView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 25.03.23.
//

import SwiftUI
private extension Bundle {
    var iconFileName: String? {
        guard let icons = infoDictionary?["CFBundleIcons"] as? [String: Any],
              let primaryIcon = icons["CFBundlePrimaryIcon"] as? [String: Any],
              let iconFiles = primaryIcon["CFBundleIconFiles"] as? [String],
              let iconFileName = iconFiles.last
        else { return nil }
        return iconFileName
    }
}

struct LogoView: View {
    private var iconImage: Image {
        Bundle.main.iconFileName
            .flatMap { UIImage(named: $0) }
            .map { Image(uiImage: $0) }!
    }

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
