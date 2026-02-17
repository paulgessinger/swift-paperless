import UIKit

struct ScannerButtonPattern {
    let accessibilityLabels: [String]
    let buttonTitles: [String]
    let controlType: ControlType
    let activationMethod: ActivationMethod

    enum ControlType: CustomStringConvertible {
        case button
        case labelledButtonWithInnerButton
        case menuButton

        var description: String {
            switch self {
            case .button: "button"
            case .labelledButtonWithInnerButton: "labelledButtonWithInnerButton"
            case .menuButton: "menuButton"
            }
        }
    }

    enum ActivationMethod: CustomStringConvertible {
        case sendActions
        case tapInnerButton
        case openMenuThenTap(menuItemTitle: String)

        var description: String {
            switch self {
            case .sendActions: "sendActions"
            case .tapInnerButton: "tapInnerButton"
            case let .openMenuThenTap(title): "openMenuThenTap(\(title))"
            }
        }
    }
}

/// When a user reports scanner settings don't work on a new iOS version:
/// 1. Ask them to share logs from Settings -> Logs
/// 2. Logs show all buttons found with their accessibility labels
/// 3. Add a new configuration for the iOS version
struct ScannerSettingsConfiguration {
    let flashPattern: ScannerButtonPattern
    let autoscanEnabledPattern: ScannerButtonPattern
    let autoscanDisabledPattern: ScannerButtonPattern
    let initialDelay: Duration
    let menuDelay: Duration

    let isSupported: Bool

    static func forCurrentOS() -> ScannerSettingsConfiguration {
        let version = ProcessInfo.processInfo.operatingSystemVersion

        switch (version.majorVersion, version.minorVersion) {
        case (18, _):
            return .iOS18Configuration
        default:
            return .fallbackConfiguration
        }
    }

    static let iOS18Configuration = ScannerSettingsConfiguration(
        flashPattern: ScannerButtonPattern(
            accessibilityLabels: ["flash settings", "Show flash settings"],
            buttonTitles: [],
            controlType: .menuButton,
            activationMethod: .openMenuThenTap(menuItemTitle: "On")
        ),
        autoscanEnabledPattern: ScannerButtonPattern(
            accessibilityLabels: ["Automatic document capture enabled"],
            buttonTitles: [],
            controlType: .labelledButtonWithInnerButton,
            activationMethod: .tapInnerButton
        ),
        autoscanDisabledPattern: ScannerButtonPattern(
            accessibilityLabels: ["Automatic document capture disabled"],
            buttonTitles: [],
            controlType: .labelledButtonWithInnerButton,
            activationMethod: .tapInnerButton
        ),
        initialDelay: .milliseconds(500),
        menuDelay: .milliseconds(300),
        isSupported: true
    )

    static let fallbackConfiguration = ScannerSettingsConfiguration(
        flashPattern: ScannerButtonPattern(
            accessibilityLabels: ["flash settings", "Show flash settings"],
            buttonTitles: [],
            controlType: .menuButton,
            activationMethod: .openMenuThenTap(menuItemTitle: "On")
        ),
        autoscanEnabledPattern: ScannerButtonPattern(
            accessibilityLabels: ["Automatic document capture enabled"],
            buttonTitles: [],
            controlType: .labelledButtonWithInnerButton,
            activationMethod: .tapInnerButton
        ),
        autoscanDisabledPattern: ScannerButtonPattern(
            accessibilityLabels: ["Automatic document capture disabled"],
            buttonTitles: [],
            controlType: .labelledButtonWithInnerButton,
            activationMethod: .tapInnerButton
        ),
        initialDelay: .milliseconds(500),
        menuDelay: .milliseconds(300),
        isSupported: false
    )
}
