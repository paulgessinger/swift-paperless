//
//  Bundle.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 13.05.2024.
//

import Foundation
import SwiftUI

extension Bundle {
    @available(iOS 17, *)
    var icon: Image? {
        #if !os(macOS)
            if let icons = infoDictionary?["CFBundleIcons"] as? [String: Any],
               let primaryIcon = icons["CFBundlePrimaryIcon"] as? [String: Any],
               let iconFiles = primaryIcon["CFBundleIconFiles"] as? [String],
               let lastIcon = iconFiles.last
            {
                if let uiImage = UIImage(named: lastIcon) {
                    return Image(uiImage: uiImage)
                }
            }
        #endif
        return nil
    }
}

extension Bundle {
    var releaseVersionNumber: String? {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    var buildVersionNumber: String? {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String
    }
}

enum AppConfiguration: String {
    case Debug, TestFlight, AppStore, Simulator
}

extension Bundle {
    // This can be used to add debug statements.
    static var isDebug: Bool {
        #if DEBUG
            return true
        #else
            return false
        #endif
    }

    var appConfiguration: AppConfiguration {
        let receiptURL = Bundle.main.appStoreReceiptURL
        let isTestFlight = receiptURL?.lastPathComponent == "sandboxReceipt"
        let isSimulator = receiptURL?.absoluteString.contains("CoreSimulator") ?? false
        if Self.isDebug {
            return .Debug
        } else if isTestFlight {
            return .TestFlight
        } else if isSimulator {
            return .Simulator
        } else {
            return .AppStore
        }
    }
}
