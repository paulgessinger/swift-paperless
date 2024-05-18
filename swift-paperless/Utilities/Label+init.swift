//
//  Label+init.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 06.05.2024.
//

import SwiftUI

extension Label where Icon == Image, Title == Text {
    init(localized: LocalizedStringResource, systemImage: String) {
        self.init(String(localized: localized), systemImage: systemImage)
    }

    init(localized: LocalizedStringResource, image: String) {
        self.init(String(localized: localized), image: image)
    }
}
