//
//  Pasteboard.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 22.09.2024.
//

#if canImport(AppKit)
    import AppKit
#endif
#if canImport(UIKit)
    import UIKit
#endif

public struct Pasteboard {
    private init() {}

    @MainActor public static var general = Pasteboard()

    public var string: String? {
        get {
            #if canImport(UIKit)
                UIPasteboard.general.string
            #elseif canImport(AppKit)
                NSPasteboard.general.string(forType: .string)
            #else
                #error("Unsupported platform")
            #endif
        }

        set {
            #if canImport(UIKit)
                UIPasteboard.general.string = newValue
            #elseif canImport(AppKit)
                if let newValue {
                    NSPasteboard.general.setString(newValue, forType: .string)
                } else {
                    NSPasteboard.general.clearContents()
                }
            #else
                #error("Unsupported platform")
            #endif
        }
    }
}
