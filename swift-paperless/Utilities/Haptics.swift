//
//  Haptics.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 22.09.2024.
//

#if canImport(UIKit)
    import UIKit
#endif

#if canImport(UIKit)
    @MainActor
    private struct HapticsInternal {
        @MainActor
        static let shared = HapticsInternal()

        let impactGenerators: [UIImpactFeedbackGenerator.FeedbackStyle: UIImpactFeedbackGenerator]

        let notificationGenerator: UINotificationFeedbackGenerator

        @MainActor
        init() {
            notificationGenerator = UINotificationFeedbackGenerator()
            let styles = [UIImpactFeedbackGenerator.FeedbackStyle]([
                .light, .heavy, .medium, .rigid, .soft,
            ])

            var impactGenerators: [UIImpactFeedbackGenerator.FeedbackStyle: UIImpactFeedbackGenerator] = [:]
            for style in styles {
                impactGenerators[style] = UIImpactFeedbackGenerator(style: style)
            }
            self.impactGenerators = impactGenerators
        }
    }
#endif

struct Haptics {
    static let shared = Haptics()

    func prepare() {
        #if canImport(UIKit)
            Task { @MainActor in
                for (_, gen) in HapticsInternal.shared.impactGenerators {
                    gen.prepare()
                }
                HapticsInternal.shared.notificationGenerator.prepare()
            }
        #endif
    }

    enum FeedbackType: Int {
        case success = 0
        case warning = 1
        case error = 2
    }

    func notification(_ type: FeedbackType) {
        #if canImport(UIKit)
            Task { @MainActor in
                HapticsInternal.shared.notificationGenerator.notificationOccurred(UINotificationFeedbackGenerator.FeedbackType(rawValue: type.rawValue)!)
            }
        #endif
    }

    enum FeedbackStyle: Int {
        case light = 0
        case medium = 1
        case heavy = 2
        case soft = 3
        case rigid = 4
    }

    func impact(style: FeedbackStyle) {
        #if canImport(UIKit)
            Task { @MainActor in
                let style = UIImpactFeedbackGenerator.FeedbackStyle(rawValue: style.rawValue)!
                guard let gen = HapticsInternal.shared.impactGenerators[style] else {
                    fatalError("Invalid feedback style")
                }
                gen.impactOccurred()
            }
        #endif
    }
}
