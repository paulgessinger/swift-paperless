//
//  LogoChangeView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 17.05.2024.
//

import Foundation
import os
import SwiftUI

enum AppIcon: String, CaseIterable {
    case primary = "AppIcon"
    case var0 = "AppIconVar0"
    case var1 = "AppIconVar1"
    case var2 = "AppIconVar2"

    var image: Image {
        Image(uiImage: UIImage(named: rawValue)!)
    }

    var name: String {
        switch self {
        case .primary: String(localized: .settings.logoPrimary)
        case .var0: String(localized: .settings.logoVariation(1))
        case .var1: String(localized: .settings.logoVariation(2))
        case .var2: String(localized: .settings.logoVariation(3))
        }
    }

    @MainActor
    var isActive: Bool {
        if let iconName = UIApplication.shared.alternateIconName {
            return iconName == rawValue
        } else {
            return self == .primary
        }
    }

    @MainActor
    static var active: AppIcon {
        if let iconName = UIApplication.shared.alternateIconName {
            return .init(rawValue: iconName) ?? .primary
        } else {
            return .primary
        }
    }
}

struct LogoChangeView: View {
    @State private var selectedIcon: AppIcon? = nil

    var body: some View {
        ScrollView(.vertical) {
            VStack {
                ForEach(AppIcon.allCases, id: \.self) { icon in
                    Button {
                        guard !icon.isActive else { return }
                        Task { @MainActor in
                            do {
                                let value = icon == .primary ? nil : icon.rawValue
                                try await UIApplication.shared.setAlternateIconName(value)
                                selectedIcon = icon
                            } catch {
                                Logger.shared.error("Error changing icon: \(error)")
                            }
                        }
                    } label: {
                        HStack {
                            icon.image
                                .resizable()
                                .aspectRatio(1, contentMode: .fit)
                                .frame(width: 60, height: 60)
                                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                            Text(icon.name)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if icon == selectedIcon {
                                Label(localized: .settings.logoIsSelected, systemImage: "checkmark.circle.fill")
                                    .labelStyle(.iconOnly)
                                    .font(.title)
                                    .foregroundStyle(.accent)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .overlay {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(icon == selectedIcon ? .accent : .gray, lineWidth: icon == selectedIcon ? 2 : 0.33)
                        }
                    }
                }
            }
            .padding()
            .animation(.default, value: selectedIcon)
        }
        .task {
            selectedIcon = .active
        }
        .navigationTitle(String(localized: .settings.logoChangeTitle))
    }
}

#Preview {
    NavigationStack {
        LogoChangeView()
    }
}
