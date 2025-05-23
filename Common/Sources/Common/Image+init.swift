//
//  Image+init.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 26.01.25.
//

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif
import SwiftUI

public extension Image {
    init?(data: Data) {
        #if canImport(UIKit)
            guard let uiImage = UIImage(data: data) else { return nil }
            self = Image(uiImage: uiImage)
        #elseif canImport(AppKit)
            guard let nsImage = NSImage(data: data) else { return nil }
            self = Image(nsImage: nsImage)
        #endif
    }
}
